//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@acala-network/contracts/oracle/IOracle.sol";
import "@acala-network/contracts/schedule/ISchedule.sol";
import "@acala-network/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Advance option contract that leverage Acala Oracle and Scheduler.
 *
 * Users are able to create options for any ERC20 asset and settles with aUSD.
 */
contract AdvancedOption is ADDRESS {
    event OptionCreated(
        uint256 indexed optionId,
        address indexed asset,
        address seller,
        address buyer,
        uint256 amount,
        uint256 strikePrice,
        uint256 settlementTime
    );
    event OptionSettled(
        uint256 indexed optionId,
        uint256 price,
        bool exercised
    );

    struct Option {
        address seller;
        address buyer;
        address asset;
        uint256 amount;
        uint256 strikePrice;
        uint256 settlementTime;
        bool settled;
    }

    IOracle public oracle = IOracle(ADDRESS.Oracle);
    ISchedule public schedule = ISchedule(ADDRESS.Schedule);
    uint256 public optionCount;
    mapping(uint256 => Option) public options;

    /**
     * @dev Create a new option.
     */
    function createOption(address asset, address buyer, uint256 amount, uint256 strikePrice, uint256 period) public {
        require(asset != address(0x0), "asset not set");
        require(buyer != address(0x0), "buyer not set");
        require(amount != 0, "amount not set");

        // Create new options
        uint256 optionId = optionCount++;
        options[optionId] = Option({
            seller: msg.sender,
            buyer: buyer,
            asset: asset,
            amount: amount,
            strikePrice: strikePrice,
            settlementTime: block.timestamp + period,
            settled: false
        });

        // Seller locks the asset in option. Seller should approve before creating options.
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Schedules the settlement call
        schedule.scheduleCall(
           address(this),   // contract address
           0,   // how much native token to send to this call
           1000000, // gas limit. funds will be reserved and refunded after the call
           5000,    // storage limit. funds will be reserved and refunded after the call
           period,  // minimum number of blocks to call
           abi.encodeWithSignature("settleOption(uint256)", optionId)
       );

        emit OptionCreated(optionId, asset, msg.sender, buyer, amount, strikePrice, block.timestamp + period);
    }

    /**
     * @dev Settles the option. Anyone can trigger the settlement.
     */
    function settleOption(uint256 optionId) public {
        Option memory option = options[optionId];
        require(!option.settled, "Option completed");
        require(option.settlementTime <= block.timestamp, "Not ready");

        // Check the latest price from Oracle
        uint256 price = oracle.getPrice(option.asset);
        // Only exercise when the price is higher than the strike price
        if (price > option.strikePrice) {
            // Settles with aUSD
            // Buyer must approve first
            IERC20(ADDRESS.AUSD).transferFrom(option.buyer, option.seller, option.amount * option.strikePrice);
            // Buyer obtain the asset
            IERC20(option.asset).transfer(option.buyer, option.amount);
        } else {
            // Otherwise, sends back the asset
            IERC20(option.asset).transfer(option.seller, option.amount);
        }

        // Update the state
        options[optionId].settled = true;

        emit OptionSettled(optionId, price, price > option.strikePrice);
    }
}