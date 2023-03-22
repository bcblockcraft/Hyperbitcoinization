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
    bool isUsdc;
}

library AccUtils {
    function globalAccValue(
        AccDeposit memory accDeposit,
        uint256 conversionRate
    ) internal view returns (uint256) {
        if (accDeposit.isUsdc) return accDeposit.globalAcc;
        return accDeposit.globalAcc * conversionRate;
    }

    function userAccValue(
        AccDeposit memory accDeposit,
        uint256 conversionRate
    ) internal pure returns (uint256) {
        if (accDeposit.isUsdc) return accDeposit.userAcc;
        return accDeposit.userAcc * conversionRate;
    }

    function depositValue(
        AccDeposit memory accDeposit,
        uint256 conversionRate
    ) internal pure returns (uint256) {
        if (accDeposit.isUsdc) return accDeposit.deposit;
        return accDeposit.deposit * conversionRate;
    }
}

contract Hyperbitcoinization {
    using SafeERC20 for IERC20;
    using AccUtils for AccDeposit;

    address public immutable btc;
    address public immutable usdc;
    address public immutable oracle;

    uint256 public immutable conversionRate;

    uint256 public immutable endTimestamp;

    mapping(address => uint256) public usdcBalance;
    mapping(address => uint256) public btcBalance;

    uint256[] public usdcAccumulator;
    mapping(address => AccDeposit[]) public usdcDepositAccumulator;

    uint256[] public btcAccumulator;
    mapping(address => AccDeposit[]) public btcDepositAccumulator;

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

    function btcInBet(address user) public view returns (uint256) {
        return _btcInBet(user);
    }

    // =================== DEPOSIT FUNCTIONS ===================

    function depositUsdc(uint256 amount) external onlyPending {
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        usdcBalance[msg.sender] += amount;
        usdcTotalDeposits += amount;

        uint256 globalAcc = _pushToGlobalAccumulator(amount, usdcAccumulator);
        _pushToDepositAccumulator(
            amount,
            globalAcc,
            usdcDepositAccumulator[msg.sender],
            true
        );

        emit UsdcDeposited(msg.sender, amount);
    }

    function depositBtc(uint256 amount) external onlyPending {
        IERC20(btc).safeTransferFrom(msg.sender, address(this), amount);
        btcBalance[msg.sender] += amount;
        btcTotalDeposits += amount;

        uint256 globalAcc = _pushToGlobalAccumulator(amount, btcAccumulator);
        _pushToDepositAccumulator(
            amount,
            globalAcc,
            btcDepositAccumulator[msg.sender],
            false
        );

        emit BtcDeposited(msg.sender, amount);
    }

    // =================== CLAIM FUNCTIONS ===================

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

        uint8 decimals = Oracle(oracle).decimals();
        uint256 answer = Oracle(oracle).latestAnswer();
        uint256 _1m = 1000000 * 10 ** decimals;

        if (answer >= _1m) winnerToken = btc;
        else if (endTimestamp <= block.timestamp) winnerToken = usdc;

        if (winnerToken != address(0)) emit WinnerSet(winnerToken);
    }

    // =================== INTERNAL FUNCTIONS ===================

    function _pushToGlobalAccumulator(
        uint256 amount,
        uint256[] storage accumulator
    ) internal returns (uint256) {
        uint256 len = accumulator.length;
        if (len == 0) accumulator.push(amount);
        else accumulator.push(accumulator[len - 1] + amount);

        return accumulator[len];
    }

    function _pushToDepositAccumulator(
        uint256 amount,
        uint256 globalAcc,
        AccDeposit[] storage _accDeposit,
        bool isUsdc
    ) internal {
        uint256 len = _accDeposit.length;
        uint256 usdcAcc = globalAcc;
        if (len == 0) {
            _accDeposit.push(AccDeposit(usdcAcc, amount, amount, isUsdc));
        } else {
            _accDeposit.push(
                AccDeposit(
                    usdcAcc,
                    _accDeposit[len - 1].userAcc + amount,
                    amount,
                    isUsdc
                )
            );
        }
    }

    function _keepUsdcTakeBtc(
        address to
    ) internal returns (uint256 usdcAmount, uint256 wbtcAmount) {
        usdcAmount = usdcBalance[msg.sender];
        wbtcAmount = _usdcInBet(msg.sender) / conversionRate;
        uint256 btcNotInBet = btcBalance[msg.sender] - _btcInBet(msg.sender);
        wbtcAmount += btcNotInBet;
        IERC20(usdc).safeTransfer(to, usdcAmount);
        IERC20(btc).safeTransfer(to, wbtcAmount);
    }

    function _keepBtcTakeUsdc(
        address to
    ) internal returns (uint256 usdcAmount, uint256 wbtcAmount) {
        wbtcAmount = btcBalance[msg.sender];
        usdcAmount = _btcInBet(msg.sender) * conversionRate;
        uint256 usdcNotInBet = usdcBalance[msg.sender] - usdcInBet(msg.sender);
        usdcAmount += usdcNotInBet;
        IERC20(usdc).safeTransfer(to, usdcAmount);
        IERC20(btc).safeTransfer(to, wbtcAmount);
    }

    function _usdcInBet(address user) internal view returns (uint256) {
        AccDeposit[] memory _accDeposit = usdcDepositAccumulator[user];
        uint256 btcValue = btcTotalDeposits * conversionRate;
        return _inBet(btcValue, _accDeposit);
    }

    function _btcInBet(address user) internal view returns (uint256) {
        AccDeposit[] memory _accDeposit = btcDepositAccumulator[user];
        return _inBet(usdcTotalDeposits, _accDeposit);
    }

    function _inBet(
        uint256 totalValue, // usdc denominated
        AccDeposit[] memory _accDeposit
    ) internal view returns (uint256) {
        uint256 len = _accDeposit.length;
        uint start = 0;
        uint end = len;

        if (len == 0) return 0;

        // if already filled, return the last balance
        AccDeposit memory lastDeposit = _accDeposit[len - 1];
        uint256 userTotal = lastDeposit.globalAcc;

        if (!lastDeposit.isUsdc) userTotal = userTotal * conversionRate;
        if (totalValue >= userTotal) return lastDeposit.userAcc;

        // otherwise perform a binary search
        while (start <= end) {
            uint mid = (start + end) / 2;

            AccDeposit memory currentDeposit = _accDeposit[mid];
            uint256 currentGlobalAcc = currentDeposit.globalAccValue(
                conversionRate
            );

            if (
                (mid == 0 && totalValue <= currentGlobalAcc) ||
                (totalValue <= currentGlobalAcc &&
                    totalValue >
                    _accDeposit[uint(mid - 1)].globalAccValue(conversionRate))
            ) {
                uint256 remaining = currentGlobalAcc - totalValue;
                if (!currentDeposit.isUsdc)
                    remaining = remaining / conversionRate;

                uint256 _min = (remaining <= currentDeposit.deposit)
                    ? remaining
                    : currentDeposit.deposit;

                return currentDeposit.userAcc - _min;
            } else if (totalValue > currentGlobalAcc) {
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
