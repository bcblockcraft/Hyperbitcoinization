// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/Oracle.sol";

struct AccDeposit {
    uint256 globalAcc;
    uint256 userAcc;
    uint256 deposit;
}

contract Hyperbitcoinization {
    using SafeERC20 for IERC20;

    address public immutable WBTC;
    address public immutable USDC;
    address public immutable oracle;

    uint256 public immutable CONVERSION_RATE;

    uint256 public immutable END_TIMESTAMP;

    mapping(address => uint256) public USDCBalance;
    mapping(address => uint256) public WBTCBalance;

    uint256[] public USDCAccBalance;
    mapping(address => AccDeposit[]) public accDeposit;

    uint256 public USDCTotalDeposits;
    uint256 public WBTCTotalDeposits;

    address public winnerToken; // its 0 before END_TIMESTAMP. if btc price > $1m its WBTC. USDC otherwise;

    mapping(address => bool) public claimed;

    event USDCDeposited(address user, uint256 amount);
    event WBTCDeposited(address user, uint256 amount);
    event Claimed(address user, uint256 usdcAmount, uint256 wbtcAmount);
    event WinnerSet(address winnerToken);

    error NotPending();
    error CapExceeded();
    error Locked();
    error NotFinished();
    error Finished();

    constructor(
        address WBTC_,
        address USDC_,
        address ORACLE_,
        uint256 END_TIMESTAMP_,
        uint256 CONVERSION_RATE_
    ) {
        WBTC = WBTC_;
        USDC = USDC_;
        oracle = ORACLE_;
        CONVERSION_RATE = CONVERSION_RATE_;

        END_TIMESTAMP = END_TIMESTAMP_;
    }

    function USDCAmountInBet(address user) public view returns (uint256) {
        return _amountInBet(user);
    }

    // =================== DEPOSIT FUNCTIONS ===================

    function depositUSDC(uint256 amount) external onlyPending {
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        USDCBalance[msg.sender] += amount;
        USDCTotalDeposits += amount;

        _updateGlobalAcc(amount);
        _updateUserAcc(amount);

        emit USDCDeposited(msg.sender, amount);
    }

    function depositWBTC(uint256 amount) external onlyPending {
        uint256 btcValueAfter = (amount + WBTCTotalDeposits) * CONVERSION_RATE;
        if (btcValueAfter > USDCTotalDeposits) revert CapExceeded();

        IERC20(WBTC).safeTransferFrom(msg.sender, address(this), amount);
        WBTCBalance[msg.sender] += amount;
        WBTCTotalDeposits += amount;

        emit WBTCDeposited(msg.sender, amount);
    }

    // =================== CLAIM FUNCTION ===================

    function claim(address to) external finished {
        if (claimed[msg.sender]) return;
        claimed[msg.sender] = true;

        uint256 usdcAmount;
        uint256 wbtcAmount;

        if (winnerToken == WBTC)
            (usdcAmount, wbtcAmount) = _keepUSDCTakeWBTC(to);
        else (usdcAmount, wbtcAmount) = _keepWBTCTakeUSDC(to);

        emit Claimed(msg.sender, usdcAmount, wbtcAmount);
    }

    function setWinnerToken() external {
        if (winnerToken != address(0)) revert Finished();
        if (block.timestamp < END_TIMESTAMP) revert NotFinished();

        uint8 decimals = Oracle(oracle).decimals();
        uint256 answer = Oracle(oracle).latestAnswer();
        uint256 _1m = 1000000 * 10 ** decimals;

        if (answer >= _1m) winnerToken = WBTC;
        else winnerToken = USDC;

        emit WinnerSet(winnerToken);
    }

    // =================== INTERNAL FUNCTIONS ===================

    function _updateGlobalAcc(uint256 amount) internal {
        uint256 len = USDCAccBalance.length;
        if (len == 0) USDCAccBalance.push(amount);
        else USDCAccBalance.push(USDCAccBalance[len - 1] + amount);
    }

    function _updateUserAcc(uint256 amount) internal {
        AccDeposit[] storage _accDeposit = accDeposit[msg.sender];
        uint256 len = _accDeposit.length;
        uint256 USDCAcc = USDCAccBalance[USDCAccBalance.length - 1]; // must be updated before this call
        if (len == 0) {
            _accDeposit.push(AccDeposit(USDCAcc, amount, amount));
        } else {
            _accDeposit.push(
                AccDeposit(
                    USDCAcc,
                    _accDeposit[len - 1].userAcc + amount,
                    amount
                )
            );
        }
    }

    function _keepUSDCTakeWBTC(
        address to
    ) internal returns (uint256 usdcAmount, uint256 wbtcAmount) {
        usdcAmount = USDCBalance[msg.sender];
        wbtcAmount = _amountInBet(msg.sender) / CONVERSION_RATE;
        IERC20(USDC).safeTransfer(to, usdcAmount);
        IERC20(WBTC).safeTransfer(to, wbtcAmount);
    }

    function _keepWBTCTakeUSDC(
        address to
    ) internal returns (uint256 usdcAmount, uint256 wbtcAmount) {
        wbtcAmount = WBTCBalance[msg.sender];
        usdcAmount = wbtcAmount * CONVERSION_RATE;
        IERC20(USDC).safeTransfer(to, usdcAmount);
        IERC20(WBTC).safeTransfer(to, wbtcAmount);
    }

    function _amountInBet(address user) internal view returns (uint256) {
        AccDeposit[] memory _accDeposit = accDeposit[user];
        uint256 WBTCValue = WBTCTotalDeposits * CONVERSION_RATE;
        uint256 len = _accDeposit.length;
        uint start = 0;
        uint end = len;

        if (len == 0) {
            return 0;
        }

        while (start <= end) {
            uint mid = (start + end) / 2;

            AccDeposit memory currentDeposit = _accDeposit[mid];
            uint256 currentGlobalAcc = currentDeposit.globalAcc;

            if (
                (mid == 0 && WBTCValue <= currentGlobalAcc) ||
                (WBTCValue <= currentGlobalAcc &&
                    WBTCValue > _accDeposit[uint(mid - 1)].globalAcc)
            ) {
                int256 remaining = int(currentGlobalAcc) - int(WBTCValue);
                if (remaining < 0) {
                    return currentDeposit.userAcc - currentDeposit.deposit;
                } else {
                    return currentDeposit.userAcc - uint(remaining);
                }
            } else if (WBTCValue > currentGlobalAcc) {
                start = mid + 1;
            } else {
                end = mid - 1;
            }
        }

        return 0;
    }

    // =================== MODIFIERS ===================

    modifier onlyPending() {
        // end timestamp is not reached and system is not locked
        if (block.timestamp <= END_TIMESTAMP) _;
        else revert NotPending();
    }

    modifier finished() {
        if (winnerToken != address(0)) _;
        else revert NotFinished();
    }
}
