// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

contract Ownable {
    address private _owner;

    /// @notice 合约所有权发生转移时触发。
    /// @param previousOwner 原所有者地址。
    /// @param newOwner 新所有者地址。
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() public {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    /// @notice 返回当前合约所有者。
    /// @return 当前所有者地址。
    function owner() public view returns (address) {
        return _owner;
    }

    /// @notice 将合约所有权转移给新的账户。
    /// @dev 新所有者地址不能为零地址。
    /// @param newOwner 接收合约所有权的地址。
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}
