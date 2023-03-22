// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Hyperbitcoinization {
    using SafeERC20 for IERC20;

    address public immutable WBTC;
    address public immutable USDC;

    uint256 public immutable USDC_MAX_CAP;
    uint256 public immutable WBTC_MAX_CAP;

    uint256 public immutable CONVERSION_RATE;

    uint256 public immutable END_TIMESTAMP;

    mapping(address => uint256) USDCBalance;
    mapping(address => uint256) WBTCBalance;

    uint256 public USDCTotalDeposits;
    uint256 public WBTCTotalDeposits;

    bool public isLocked;

    error CapExceeded();
    error NotPending();
    error Locked();
    error NotSettled();

    constructor(
        address WBTC_,
        address USDC_,
        uint256 USDC_MAX_CAP_,
        uint256 END_TIMESTAMP_,
        uint256 CONVERSION_RATE_
    ) {
        WBTC = WBTC_;
        USDC = USDC_;

        USDC_MAX_CAP = USDC_MAX_CAP_;
        WBTC_MAX_CAP = USDC_MAX_CAP_ / CONVERSION_RATE_;

        CONVERSION_RATE = CONVERSION_RATE_;

        END_TIMESTAMP = END_TIMESTAMP_;
    }

    // =================== DEPOSIT FUNCTIONS ===================
    // these functions can be used to deposit USDC/WBTC.
    // users can deposit while the bet is pending.
    // the bet is pending if the end timestamp is not reached and system is not locked
    // system is not locked if max cap of USDC and WBTC is not reached

    function depositUSDC(uint256 amount) external onlyPending {
        if (amount + USDCTotalDeposits > USDC_MAX_CAP) revert CapExceeded();

        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        USDCBalance[msg.sender] += amount;
        USDCTotalDeposits += amount;

        if (_canBeLocked()) isLocked = true;
    }

    function depositWBTC(uint256 amount) external onlyPending {
        if (amount + WBTCTotalDeposits > WBTC_MAX_CAP) revert CapExceeded();

        IERC20(WBTC).safeTransferFrom(msg.sender, address(this), amount);
        WBTCBalance[msg.sender] += amount;
        WBTCTotalDeposits += amount;

        if (_canBeLocked()) isLocked = true;
    }

    // =================== WITHDRAW FUNCTIONS ===================
    // these functions can be used to withdraw deposited USDC/WBTC
    // users can withdraw if the system is not locked.

    function withdrawUSDC(uint256 amount, address to) external notLocked {
        USDCBalance[msg.sender] -= amount;
        USDCTotalDeposits -= amount;
        IERC20(USDC).safeTransfer(to, amount);
    }

    function withdrawWBTC(uint256 amount, address to) external notLocked {
        WBTCBalance[msg.sender] -= amount;
        WBTCTotalDeposits -= amount;
        IERC20(WBTC).safeTransfer(to, amount);
    }

    // =================== CLAIM FUNCTIONS ===================
    // these functions can be used to claim USDC/WBTC
    // users can claim if bet is settled.
    // bet is settled if end timestamp is reached and system is locked.

    function claimUSDC(address to) external settled {
        // user can claim USDC in proportion to WBTC deposit
        uint256 claimAmount = WBTCBalance[msg.sender] * CONVERSION_RATE;
        WBTCBalance[msg.sender] = 0;
        IERC20(USDC).safeTransfer(to, claimAmount);
    }

    function claimWBTC(address to) external settled {
        uint256 claimAmount = USDCBalance[msg.sender] / CONVERSION_RATE;
        USDCBalance[msg.sender] = 0;
        IERC20(WBTC).safeTransfer(to, claimAmount);
    }

    // =================== INTERNAL FUNCTIONS ===================

    function _canBeLocked() internal view returns (bool) {
        return (USDCTotalDeposits == USDC_MAX_CAP &&
            WBTCTotalDeposits == WBTC_MAX_CAP);
    }

    // =================== MODIFIERS ===================

    modifier onlyPending() {
        // end timestamp is not reached and system is not locked
        if (!isLocked && block.timestamp <= END_TIMESTAMP) _;
        else revert NotPending();
    }

    modifier notLocked() {
        if (!isLocked) _;
        else revert Locked();
    }

    modifier settled() {
        if (isLocked && block.timestamp > END_TIMESTAMP) _;
        else revert NotSettled();
    }
}
