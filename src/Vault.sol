    // SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IGauge} from "velodrome-finance/contracts/interfaces/IGauge.sol";
import {IPool} from "velodrome-finance/contracts/interfaces/IPool.sol";
import {IRouter} from "velodrome-finance/contracts/interfaces/IRouter.sol";
import {IVoter} from "velodrome-finance/contracts/interfaces/IVoter.sol";
import {Pool} from "velodrome-finance/contracts/Pool.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Tranche} from "./Tranche.sol";

/// @title Vault
contract Vault {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    uint16 public immutable feeBasisPoints;
    address public immutable gauge;
    address public immutable maker;
    uint16 public immutable makerRevenueBasisPoints;
    address public immutable makerToken;
    uint256 public immutable maturity;
    address public immutable pool;
    address public immutable rewardToken;
    address public immutable router;
    uint16 private slippageBasisPoints;
    bool public immutable stable;
    address public immutable takerToken;
    bool public trancheCreationEnabled = true;
    address public immutable vaultFactory;
    uint16 public constant BPS = 10_000;
    EnumerableSet.AddressSet private _tranches;

    error ExceedsMaxBPS(uint256 bps, uint256 maxBPS);
    error InsufficientAmount(address token, uint256 amount);
    error InsufficientBalance(uint256 amount, uint256 balance);
    error TrancheCreationDisabled();
    error TransferFailure(address token, address to, uint256 amount);
    error Unauthorized(address caller, address authority);

    modifier authorized(address _authority) {
        if (msg.sender != _authority) revert Unauthorized({caller: msg.sender, authority: _authority});
        _;
    }

    modifier validAmount(address _token, uint256 _amount) {
        if (_amount == 0 || _amount > 0 && _amount > IERC20(_token).allowance(msg.sender, address(this))) {
            revert InsufficientAmount({token: _token, amount: _amount});
        }
        _;
    }

    modifier validBasisPoints(uint16 _feeBasisPoints) {
        if (_feeBasisPoints > BPS) revert ExceedsMaxBPS({bps: _feeBasisPoints, maxBPS: BPS});
        _;
    }

    constructor(
        uint16 _feeBasisPoints,
        address _maker,
        uint16 _makerRevenueBasisPoints,
        address _makerToken,
        uint256 _maturity,
        address _router,
        uint16 _slippageBasisPoints,
        bool _stable,
        address _takerToken
    ) validBasisPoints(_feeBasisPoints) validBasisPoints(_makerRevenueBasisPoints) {
        require(_takerToken != address(0), "takerToken address cannot be zero");
        require(_makerToken != address(0), "makerToken address cannot be zero");
        require(_router != address(0), "router address cannot be zero");
        require(_maker != address(0), "maker address cannot be zero");
        pool = IRouter(_router).poolFor(_makerToken, _takerToken, _stable, IRouter(_router).defaultFactory());
        IVoter voter = IVoter(IRouter(_router).voter());
        require(pool != address(0), "pool address cannot be zero");

        feeBasisPoints = _feeBasisPoints;
        gauge = voter.gauges(pool);
        maker = _maker;
        makerRevenueBasisPoints = _makerRevenueBasisPoints;
        makerToken = _makerToken;
        maturity = _maturity;
        rewardToken = IGauge(gauge).rewardToken();
        router = _router;
        slippageBasisPoints = _slippageBasisPoints;
        stable = _stable;
        takerToken = _takerToken;
        vaultFactory = msg.sender;
    }

    /// @notice deposits maker tokens into the vault
    /// @dev the maker/caller must approve sending the funds to the vault prior to calling this function
    /// @param _amount amount of maker tokens to deposit
    function depositTokens(uint256 _amount) external authorized(maker) validAmount(makerToken, _amount) {
        IERC20(makerToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    // TODO
    function getQuoteAmounts(uint256 _takerAmount) public view returns (uint256, uint256) {
        (uint256 quoteAmountA, uint256 quoteAmountB,) = IRouter(router).quoteAddLiquidity(
            makerToken,
            takerToken,
            stable,
            IPool(pool).factory(),
            IERC20(makerToken).balanceOf(address(this)),
            _takerAmount
        );
        return (quoteAmountA, quoteAmountB);
    }

    /// @notice Uses token1 provided by the taker (caller) to create a new tranche with existing maker tokens
    /// @dev the taker must approve the router to spend the taker token prior to the call
    /// @param _takerAmount amount of token1 provided by the taker
    /// @return tranche address of the newly created tranche
    /// @return vaultDeposit amount of token0 deposited by the vault into the tranche, which was added to the LP
    /// @return takerDeposit amount of token1 deposited by the taker into the tranche, which was added to the LP
    /// @return liquidity amount of LP tokens minted for the tranche
    function createTranche(uint256 _takerAmount)
        external
        validAmount(takerToken, _takerAmount)
        returns (address, uint256, uint256, uint256)
    {
        if (!trancheCreationEnabled) revert TrancheCreationDisabled();
        Tranche tranche = new Tranche(block.timestamp + maturity, msg.sender);

        (uint256 quoteAmountA, uint256 quoteAmountB) = getQuoteAmounts(_takerAmount);

        IERC20(takerToken).safeTransferFrom(msg.sender, address(this), quoteAmountB);
        IERC20(makerToken).approve(router, quoteAmountA);
        IERC20(takerToken).approve(router, quoteAmountB);

        (uint256 vaultDeposit, uint256 takerDeposit, uint256 liquidity) = IRouter(router).addLiquidity(
            makerToken,
            takerToken,
            stable,
            quoteAmountA,
            quoteAmountB,
            0, // amountAMin
            0, // amountBMin
            address(tranche),
            block.timestamp
        );

        tranche.stakeLiquidity(liquidity);
        IERC20(takerToken).safeTransfer(msg.sender, IERC20(takerToken).balanceOf(address(this)));
        _tranches.add(address(tranche));
        return (address(tranche), vaultDeposit, takerDeposit, liquidity);
    }

    function makerWithdrawTokensFromVault(uint256 _amount) external authorized(maker) {
        if (_amount == 0) revert InsufficientAmount({token: makerToken, amount: _amount});
        if (_amount > IERC20(makerToken).balanceOf(address(this))) {
            revert InsufficientBalance({amount: _amount, balance: IERC20(makerToken).balanceOf(address(this))});
        }
        bool transferToMaker = IERC20(makerToken).transfer(msg.sender, _amount);
        if (!transferToMaker) revert TransferFailure({token: makerToken, to: address(msg.sender), amount: _amount});
    }

    function enableTrancheCreation() external authorized(maker) {
        trancheCreationEnabled = true;
    }

    function disableTrancheCreation() external authorized(maker) {
        trancheCreationEnabled = false;
    }

    /// @return number of tranches
    function getTranchesSize() public view returns (uint256) {
        return _tranches.length();
    }

    function getSlippageBasisPoints() public view returns (uint16) {
        return slippageBasisPoints;
    }

    /// @param _slippageBasisPoints the new, maximum amount of slippage in basis points that the maker will accept
    function setSlippageBasisPoints(uint16 _slippageBasisPoints)
        external
        authorized(maker)
        validBasisPoints(_slippageBasisPoints)
    {
        slippageBasisPoints = _slippageBasisPoints;
    }

    function tranches() external view returns (address[] memory) {
        return _tranches.values();
    }
}
