// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
}
