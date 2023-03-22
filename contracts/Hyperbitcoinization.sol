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

    error NotPending();
    error CapExceeded();
    error Locked();
    error NotFinished();

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

    // =================== DEPOSIT FUNCTIONS ===================

    function depositUSDC(uint256 amount) external onlyPending {
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        USDCBalance[msg.sender] += amount;
        USDCTotalDeposits += amount;

        // update global USDC deposits accumulator
        uint256 globalAccLen = USDCAccBalance.length;
        if (globalAccLen == 0) USDCAccBalance.push(amount);
        else USDCAccBalance.push(USDCAccBalance[globalAccLen - 1] + amount);

        // update user deposit accumulator
        AccDeposit[] storage _accDeposit = accDeposit[msg.sender];
        uint256 userAccLen = _accDeposit.length;
        if (userAccLen == 0) {
            _accDeposit.push(
                AccDeposit(USDCAccBalance[globalAccLen], amount, amount)
            );
        } else {
            _accDeposit.push(
                AccDeposit(
                    USDCAccBalance[globalAccLen],
                    _accDeposit[userAccLen - 1].userAcc + amount,
                    amount
                )
            );
        }
    }

    function depositWBTC(uint256 amount) external onlyPending {
        uint256 btcValueAfter = (amount + WBTCTotalDeposits) * CONVERSION_RATE;
        if (btcValueAfter > USDCTotalDeposits) revert CapExceeded();

        IERC20(WBTC).safeTransferFrom(msg.sender, address(this), amount);
        WBTCBalance[msg.sender] += amount;
        WBTCTotalDeposits += amount;
    }

    // =================== CLAIM FUNCTIONS ===================
    // these functions can be used to claim USDC/WBTC
    // users can claim if bet is settled.

    function USDCAmountInBet(address user) public view returns (uint256) {
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

    function claim(address to) external finished {
        // user can claim USDC in proportion to WBTC deposit
        if (winnerToken == WBTC) {
            _settleWBTC(msg.sender, to);
        } else {
            _settleUSDC(msg.sender, to);
            _settleNotInBet(msg.sender, to);
        }
    }

    function setWinnerToken() external {
        if (block.timestamp < END_TIMESTAMP) revert NotFinished();
        uint8 decimals = Oracle(oracle).decimals();
        uint256 answer = Oracle(oracle).latestAnswer();
        uint256 _1m = 1000000 * 10 ** decimals;
        if (answer > _1m) winnerToken = WBTC;
        else winnerToken = USDC;
    }

    function _settleUSDC(address user, address to) internal {
        uint256 WBTCAmount = WBTCBalance[user];
        uint256 USDCClaimAmount = WBTCAmount * CONVERSION_RATE;
        WBTCBalance[user] = 0;
        IERC20(USDC).safeTransfer(to, USDCClaimAmount);
        IERC20(WBTC).safeTransfer(to, WBTCAmount);
    }

    function _settleWBTC(address user, address to) internal {
        uint256 USDCAmount = USDCBalance[user];
        if (USDCAmount == 0) return;
        USDCBalance[user] = 0;
        uint256 USDCInBet = USDCAmountInBet(user);
        uint256 WBTCAmount = USDCInBet / CONVERSION_RATE;
        IERC20(USDC).safeTransfer(to, USDCAmount);
        IERC20(WBTC).safeTransfer(to, WBTCAmount);
    }

    function _settleNotInBet(address user, address to) internal {
        uint256 USDCAmount = USDCBalance[user];
        uint256 amount = USDCAmount - USDCAmountInBet(user);
        USDCBalance[user] = 0;
        IERC20(USDC).safeTransfer(to, amount);
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
