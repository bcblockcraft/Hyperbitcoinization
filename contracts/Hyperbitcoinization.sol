// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Hyperbitcoinization {
    using SafeERC20 for ERC20;

    enum State {
        PENDING,
        INITIALIZED
    }

    address public immutable WBTC;
    address public immutable USDC;
    uint256 public immutable END_TIMESTAMP;
    uint256 public immutable CONVERSION_RATE; // btc/usdc

    mapping(address => mapping(address => uint)) public balance; // token => (user => balance)
    mapping(address => uint256) public totalDeposits;
    mapping(address => uint256) public maxCap; // token => max cap

    State public state;

    error CapExceeded();
    error NotFinished();
    error InvalidToken();
    error NotPending();

    constructor(
        address WBTC_,
        address USDC_,
        uint256 USDC_MAX_CAP_,
        uint256 END_TIMESTAMP_,
        uint256 CONVERSION_RATE_
    ) {
        WBTC = WBTC_;
        USDC = USDC_;
        CONVERSION_RATE = CONVERSION_RATE_;
        END_TIMESTAMP = END_TIMESTAMP_;

        maxCap[USDC] = USDC_MAX_CAP_;
        maxCap[WBTC] = USDC_MAX_CAP_ * CONVERSION_RATE;

        state = State.PENDING;
    }

    function deposit(
        address token,
        uint256 amount
    ) external validToken(token) onlyPending {
        if (amount + totalDeposits[token] > maxCap[token]) revert CapExceeded();

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        balance[token][msg.sender] += amount;
        totalDeposits[token] += amount;

        if (_canInitialize()) state = State.INITIALIZED;
    }

    function _canInitialize() internal view returns (bool) {
        return (totalDeposits[USDC] == maxCap[USDC] &&
            totalDeposits[WBTC] == maxCap[WBTC]);
    }

    modifier onlyPending() {
        if (state != State.PENDING || block.timestamp > END_TIMESTAMP) revert NotPending();
        _;
    }

    modifier validToken(address token) {
        if (!(token == WBTC || token == USDC)) revert InvalidToken();
        _;
    }

    modifier
}
