// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IGauge} from "velodrome-finance/contracts/interfaces/IGauge.sol";
import {IRouter} from "velodrome-finance/contracts/interfaces/IRouter.sol";
import {IVoter} from "velodrome-finance/contracts/interfaces/IVoter.sol";
import {Pool} from "velodrome-finance/contracts/Pool.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Vault} from "./Vault.sol";
import {VaultFactory} from "./VaultFactory.sol";

/// @title Tranche
contract Tranche {
    using SafeERC20 for IERC20;

    uint256 public immutable maturityTimestamp;
    address public immutable taker;
    address public immutable vault;

    bool private makerEmergencyBypass = false;
    bool private takerEmergencyBypass = false;

    error InvalidMaturity();
    error MaturityNotReached();
    error Unauthorized();

    modifier authorized(address _authority) {
        if (msg.sender != _authority) revert Unauthorized();
        _;
    }

    modifier isInvestor() {
        bool investor = (msg.sender == Vault(vault).maker()) || (msg.sender == taker);
        if (!investor) revert Unauthorized();
        _;
    }

    modifier maturityReached() {
        bool emergency = makerEmergencyBypass && takerEmergencyBypass;
        if (block.timestamp < maturityTimestamp && !emergency) revert MaturityNotReached();
        _;
    }

    modifier validMaturity(uint256 _maturityTimestamp) {
        if (_maturityTimestamp <= block.timestamp) revert InvalidMaturity();
        _;
    }

    constructor(uint256 _maturityTimestamp, address _taker) validMaturity(_maturityTimestamp) {
        require(_taker != address(0), "taker address cannot be zero");
        maturityTimestamp = _maturityTimestamp;
        taker = _taker;
        vault = msg.sender;
    }

    function addLiquidity() external returns (uint256, uint256, uint256) {
        uint256 makerBalance = IERC20(Vault(vault).makerToken()).balanceOf(address(this));
        uint256 takerBalance = IERC20(Vault(vault).takerToken()).balanceOf(address(this));
        bool makerApproval = IERC20(Vault(vault).makerToken()).approve(Vault(vault).router(), makerBalance);
        bool takerApproval = IERC20(Vault(vault).takerToken()).approve(Vault(vault).router(), takerBalance);
        if (!makerApproval && !takerApproval) revert("Approval failed");

        (uint256 makerDeposit, uint256 takerDeposit, uint256 liquidity) = IRouter(Vault(vault).router()).addLiquidity(
            Vault(vault).makerToken(),
            Vault(vault).takerToken(),
            Vault(vault).stable(),
            makerBalance,
            takerBalance,
            1,
            1,
            address(this),
            block.timestamp
        );

        uint256 remainingMakerBalance = IERC20(Vault(vault).makerToken()).balanceOf(address(this));
        if (remainingMakerBalance > 0) IERC20(Vault(vault).makerToken()).safeTransfer(vault, remainingMakerBalance);

        uint256 remainingTakerBalance = IERC20(Vault(vault).takerToken()).balanceOf(address(this));
        if (remainingTakerBalance > 0) IERC20(Vault(vault).takerToken()).safeTransfer(taker, remainingTakerBalance);

        address gauge = getGauge();
        address pool = Vault(vault).getPool();
        //        bool approval = Pool(Vault(vault).pool()).approve(gauge, liquidity);
        bool approval = Pool(pool).approve(gauge, liquidity);
        if (!approval) revert("Approval failed");

        IGauge(gauge).deposit(liquidity);

        return (makerDeposit, takerDeposit, liquidity);
    }

    function getGauge() public view returns (address) {
        Vault v = Vault(vault);
        address pool = v.getPool();
        IVoter voter = IVoter(IRouter(v.router()).voter());
        address gauge = voter.gauges(pool);
        return gauge;
    }

    function getRewardToken() public view returns (address) {
        address gauge = getGauge();
        address rewardToken = IGauge(gauge).rewardToken();
        return rewardToken;
    }

    function withdrawTokens()
        public
        isInvestor
        maturityReached
        returns (uint256 makerWithdrawal, uint256 takerWithdrawal)
    {
        address gauge = getGauge();
        uint256 liquidity = IGauge(gauge).balanceOf(address(this));
        IGauge(gauge).withdraw(liquidity);
        IRouter router = IRouter(Vault(vault).router());

        address pool = Vault(vault).getPool();
        bool approval = Pool(pool).approve(address(router), liquidity);
        if (!approval) revert("Approval failed");

        (uint256 _makerWithdrawal, uint256 _takerWithdrawal) = router.removeLiquidity(
            Vault(vault).makerToken(),
            Vault(vault).takerToken(),
            Vault(vault).stable(),
            liquidity,
            0,
            0,
            address(this),
            block.timestamp
        );
        uint256 trancheMakerTokens = IERC20(Vault(vault).makerToken()).balanceOf(address(this));
        IERC20(Vault(vault).makerToken()).safeTransfer(vault, trancheMakerTokens);
        uint256 trancheTakerTokens = IERC20(Vault(vault).takerToken()).balanceOf(address(this));
        IERC20(Vault(vault).takerToken()).safeTransfer(taker, trancheTakerTokens);
        return (_makerWithdrawal, _takerWithdrawal);
    }

    function withdrawRewards() public isInvestor returns (uint256 makerRewards, uint256 takerRewards, uint256 fees) {
        address gauge = getGauge();
        IGauge(gauge).getReward(address(this));
        address rewardToken = getRewardToken();

        uint256 rewardBalance = IERC20(rewardToken).balanceOf(address(this));
        uint256 _fees = rewardBalance * Vault(vault).feeBasisPoints() / Vault(vault).BPS();
        uint256 rewardsPostFees = rewardBalance - _fees;
        uint256 _makerRewards = rewardsPostFees * Vault(vault).makerRevenueBasisPoints() / Vault(vault).BPS();
        uint256 _takerRewards = rewardsPostFees - _makerRewards;

        IERC20(rewardToken).safeTransfer(Vault(vault).maker(), _makerRewards);
        IERC20(rewardToken).safeTransfer(taker, _takerRewards);
        IERC20(rewardToken).safeTransfer(VaultFactory(Vault(vault).vaultFactory()).owner(), _fees);

        return (_makerRewards, _takerRewards, _fees);
    }

    function emergencyLiquidation() public isInvestor returns (uint256, uint256) {
        if (msg.sender == Vault(vault).maker()) {
            makerEmergencyBypass = true;
        } else if (msg.sender == taker) {
            takerEmergencyBypass = true;
        }

        if (makerEmergencyBypass && takerEmergencyBypass) {
            (uint256 makerWithdrawal, uint256 takerWithdrawal) = withdrawTokens();
            return (makerWithdrawal, takerWithdrawal);
        }
        return (0, 0);
    }

    function makerSetEmergencyBypass() external authorized(Vault(vault).maker()) {
        makerEmergencyBypass = true;
    }

    function takerSetEmergencyBypass() external authorized(taker) {
        takerEmergencyBypass = true;
    }
}
