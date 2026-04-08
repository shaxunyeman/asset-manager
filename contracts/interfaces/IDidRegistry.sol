// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

interface IDidRegistry {
    /// @notice 返回账户当前绑定且处于激活状态的 DID。
    /// @dev 当账户未绑定 DID 或 DID 已失效时回退。
    /// @param account 待查询的账户地址。
    /// @return 账户当前激活的 DID 字符串。
    function getActiveDid(address account) external view returns (string memory);

    /// @notice 检查指定 DID 是否处于激活状态。
    /// @param did 待查询的 DID。
    /// @return 若 DID 已存在且处于激活状态则返回 true，否则返回 false。
    function isDidActive(string calldata did) external view returns (bool);
}
