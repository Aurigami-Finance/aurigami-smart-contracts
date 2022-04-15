pragma solidity 0.8.11;

contract TimeQuery {
    function getTime() external view returns (uint256){
        return block.timestamp;
    }
}
