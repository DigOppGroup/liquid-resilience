// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPool} from "velodrome-finance/contracts/interfaces/IPool.sol";
import {IRouter} from "velodrome-finance/contracts/interfaces/IRouter.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Tranche} from "./Tranche.sol";

/// @title Vault
contract Vault {
    using SafeERC20 for IERC20;

    uint16 public immutable feeBasisPoints;
    address public immutable maker;
    uint16 public immutable makerRevenueBasisPoints;
    address public immutable makerToken;
    uint256 public immutable maturity;
    address public immutable router;
    address public immutable takerToken;
    bool public trancheCreationEnabled = true;
    bool public immutable stable;
    address public immutable vaultFactory;
    uint16 public constant BPS = 10_000;
    address[] public tranches;

    error ExceedsMaxBPS(uint256 bps, uint256 maxBPS);
    error InsufficientAmount(uint256 amount);
    error InsufficientBalance(uint256 amount, uint256 balance);
    error TrancheCreationDisabled();
    error TransferFailure(address token, address to, uint256 amount);
    error Unauthorized(address caller, address authority);

    modifier authorized(address _authority) {
        if (msg.sender != _authority) revert Unauthorized({caller: msg.sender, authority: _authority});
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
        bool _stable,
        address _takerToken
    ) validBasisPoints(_feeBasisPoints) validBasisPoints(_makerRevenueBasisPoints) {
        require(_takerToken != address(0), "takerToken address cannot be zero");
        require(_makerToken != address(0), "makerToken address cannot be zero");
        require(_router != address(0), "router address cannot be zero");
        require(_maker != address(0), "maker address cannot be zero");
        address pool = IRouter(_router).poolFor(_makerToken, _takerToken, _stable, IRouter(_router).defaultFactory());
        require(pool != address(0), "pool address cannot be zero");

        feeBasisPoints = _feeBasisPoints;
        maker = _maker;
        makerRevenueBasisPoints = _makerRevenueBasisPoints;
        makerToken = _makerToken;
        maturity = _maturity;
        router = _router;
        stable = _stable;
        takerToken = _takerToken;
        vaultFactory = msg.sender;
    }

    /// @notice deposits maker tokens into the vault
    /// @dev the maker/caller must approve sending the funds to the vault prior to calling this function
    /// @param _amount amount of maker tokens to deposit
    function depositTokens(uint256 _amount) external authorized(maker) {
        if (_amount == 0) revert InsufficientAmount({amount: _amount});
        IERC20(makerToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Uses token1 provided by the taker (caller) to create a new tranche with existing maker tokens
    /// @dev the taker must approve the router to spend the taker token prior to the call
    /// @param _takerAmount amount of token1 provided by the taker
    /// @return tranche address of the newly created tranche
    /// @return makerDeposit amount of token0 deposited by the maker into the tranche, which was added to the LP
    /// @return takerDeposit amount of token1 deposited by the taker into the tranche, which was added to the LP
    /// @return liquidity amount of LP tokens minted for the tranche
    function createTranche(uint256 _takerAmount) external returns (address, uint256, uint256, uint256) {
        if (!trancheCreationEnabled) revert TrancheCreationDisabled();
        if (_takerAmount == 0) revert InsufficientAmount({amount: _takerAmount});
        Tranche _tranche = new Tranche(block.timestamp + maturity, msg.sender);
        tranches.push(address(_tranche));

        address pool = getPool();
        IERC20(takerToken).safeTransferFrom(msg.sender, address(this), _takerAmount);
        (uint256 quoteAmountA, uint256 quoteAmountB,) = IRouter(router).quoteAddLiquidity(
            makerToken,
            takerToken,
            stable,
            IPool(pool).factory(),
            IERC20(makerToken).balanceOf(address(this)),
            _takerAmount
        );

        bool makerTransferToTranche = IERC20(makerToken).transfer(address(_tranche), quoteAmountA);
        if (!makerTransferToTranche) {
            revert TransferFailure({token: makerToken, to: address(_tranche), amount: quoteAmountA});
        }
        bool takerTransferToTranche = IERC20(takerToken).transfer(address(_tranche), quoteAmountB);
        if (!takerTransferToTranche) {
            revert TransferFailure({token: takerToken, to: address(_tranche), amount: quoteAmountB});
        }

        (uint256 _makerDeposit, uint256 _takerDeposit, uint256 _liquidity) = _tranche.addLiquidity();

        return (address(_tranche), _makerDeposit, _takerDeposit, _liquidity);
    }

    function makerWithdrawTokensFromVault(uint256 _amount) external authorized(maker) {
        if (_amount == 0) revert InsufficientAmount({amount: _amount});
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
        return tranches.length;
    }

    function getPool() public view returns (address) {
        address pool = IRouter(router).poolFor(makerToken, takerToken, stable, IRouter(router).defaultFactory());
        return pool;
    }
}
