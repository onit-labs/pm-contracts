// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { OnitInfiniteOutcomeDPMOutcomeDomain } from "@src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMOutcomeDomain.sol";

/**
 * @notice Harness for exposing the OnitInfiniteOutcomeDPMOutcomeDomain internal functions
 */
contract OnitInfiniteOutcomeDPMOutcomeDomainHarness is OnitInfiniteOutcomeDPMOutcomeDomain {
   
   constructor(
    int256 _outcomeUnit
   )
   {
    _initializeOutcomeDomain(_outcomeUnit);
   }
   
   function updateHoldings(address trader, int256[] memory bucketIds, int256[] memory amounts) public {
    _updateHoldings(trader, bucketIds, amounts);
   }

   function getOutstandingSharesInBuckets(int256[] memory bucketIds) public view returns (int256[] memory) {
    return _getOutstandingSharesInBuckets(bucketIds);
   }

   // function bucketIdToPackedPosition(int256 bucketId) public view returns (uint256, uint256) {
   //  _bucketIdToPackedPosition(bucketId);
   // }
}
