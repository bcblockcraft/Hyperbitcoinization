// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface Oracle {
    function latestAnswer() external returns (uint256);

    function decimals() external returns (uint8);
}

struct AccDeposit {
    uint256 globalAcc;
    uint256 userAcc;
    uint256 deposit;
}

contract Hyperbitcoinization {
    using SafeERC20 for IERC20;

    address public immutable btc;
    address public immutable usdc;
    address public immutable oracle;

    uint256 public immutable conversionRate;

    uint256 public immutable endTimestamp;

    mapping(address => uint256) public usdcBalance;
    mapping(address => uint256) public btcBalance;

    uint256[] public usdcAccBalance;
    mapping(address => AccDeposit[]) public accDeposit;

    uint256 public usdcTotalDeposits;
    uint256 public btcTotalDeposits;

    address public winnerToken; // its 0 before endTimestamp. if btc price > $1m its WBTC. USDC otherwise;

    mapping(address => bool) public claimed;

    event UsdcDeposited(address user, uint256 amount);
    event BtcDeposited(address user, uint256 amount);
    event Claimed(address user, uint256 usdcAmount, uint256 wbtcAmount);
    event WinnerSet(address winnerToken);

    error NotPending();
    error CapExceeded();
    error Locked();
    error NotFinished();
    error Finished();

    constructor(
        address wbtc_,
        address usdc_,
        address oracle_,
        uint256 endTimestamp_,
        uint256 conversionRate_
    ) {
        btc = wbtc_;
        usdc = usdc_;
        oracle = oracle_;
        conversionRate = conversionRate_;

        endTimestamp = endTimestamp_;
    }

    function usdcInBet(address user) public view returns (uint256) {
        return _usdcInBet(user);
    }

    // =================== DEPOSIT FUNCTIONS ===================

    function depositUsdc(uint256 amount) external onlyPending {
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        usdcBalance[msg.sender] += amount;
        usdcTotalDeposits += amount;

        _updateGlobalAcc(amount);
        _updateUserAcc(amount);

        emit UsdcDeposited(msg.sender, amount);
    }

    function depositBtc(uint256 amount) external onlyPending {
        uint256 btcValueAfter = (amount + btcTotalDeposits) * conversionRate;
        if (btcValueAfter > usdcTotalDeposits) revert CapExceeded();

        IERC20(btc).safeTransferFrom(msg.sender, address(this), amount);
        btcBalance[msg.sender] += amount;
        btcTotalDeposits += amount;

        emit BtcDeposited(msg.sender, amount);
    }

    // =================== CLAIM FUNCTION ===================

    function claim(address to) external finished {
        if (claimed[msg.sender]) return;
        claimed[msg.sender] = true;

        uint256 usdcAmount;
        uint256 wbtcAmount;

        if (winnerToken == btc) (usdcAmount, wbtcAmount) = _keepUsdcTakeBtc(to);
        else (usdcAmount, wbtcAmount) = _keepBtcTakeUsdc(to);

        emit Claimed(msg.sender, usdcAmount, wbtcAmount);
    }

    function setWinnerToken() external {
        if (winnerToken != address(0)) revert Finished();
        if (block.timestamp < endTimestamp) revert NotFinished();

        uint8 decimals = Oracle(oracle).decimals();
        uint256 answer = Oracle(oracle).latestAnswer();
        uint256 _1m = 1000000 * 10 ** decimals;

        if (answer >= _1m) winnerToken = btc;
        else winnerToken = usdc;

        emit WinnerSet(winnerToken);
    }

    // =================== INTERNAL FUNCTIONS ===================

    function _updateGlobalAcc(uint256 amount) internal {
        uint256 len = usdcAccBalance.length;
        if (len == 0) usdcAccBalance.push(amount);
        else usdcAccBalance.push(usdcAccBalance[len - 1] + amount);
    }

    function _updateUserAcc(uint256 amount) internal {
        AccDeposit[] storage _accDeposit = accDeposit[msg.sender];
        uint256 len = _accDeposit.length;
        uint256 usdcAcc = usdcAccBalance[usdcAccBalance.length - 1]; // must be updated before this call
        if (len == 0) {
            _accDeposit.push(AccDeposit(usdcAcc, amount, amount));
        } else {
            _accDeposit.push(
                AccDeposit(
                    usdcAcc,
                    _accDeposit[len - 1].userAcc + amount,
                    amount
                )
            );
        }
    }

    function _keepUsdcTakeBtc(
        address to
    ) internal returns (uint256 usdcAmount, uint256 wbtcAmount) {
        usdcAmount = usdcBalance[msg.sender];
        wbtcAmount = _usdcInBet(msg.sender) / conversionRate;
        IERC20(usdc).safeTransfer(to, usdcAmount);
        IERC20(btc).safeTransfer(to, wbtcAmount);
    }

    function _keepBtcTakeUsdc(
        address to
    ) internal returns (uint256 usdcAmount, uint256 wbtcAmount) {
        wbtcAmount = btcBalance[msg.sender];
        usdcAmount = wbtcAmount * conversionRate;
        uint256 usdcNotInBet = usdcBalance[msg.sender] - usdcInBet(msg.sender);
        usdcAmount += usdcNotInBet;
        IERC20(usdc).safeTransfer(to, usdcAmount);
        IERC20(btc).safeTransfer(to, wbtcAmount);
    }

    function _usdcInBet(address user) internal view returns (uint256) {
        AccDeposit[] memory _accDeposit = accDeposit[user];
        uint256 btcValue = btcTotalDeposits * conversionRate;
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
                (mid == 0 && btcValue <= currentGlobalAcc) ||
                (btcValue <= currentGlobalAcc &&
                    btcValue > _accDeposit[uint(mid - 1)].globalAcc)
            ) {
                int256 remaining = int(currentGlobalAcc) - int(btcValue);
                if (remaining < 0) {
                    return currentDeposit.userAcc - currentDeposit.deposit;
                } else {
                    return currentDeposit.userAcc - uint(remaining);
                }
            } else if (btcValue > currentGlobalAcc) {
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
        if (block.timestamp <= endTimestamp) _;
        else revert NotPending();
    }

    modifier finished() {
        if (winnerToken != address(0)) _;
        else revert NotFinished();
    }
}
