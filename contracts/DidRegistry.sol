// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

import "./access/Ownable.sol";

contract DidRegistry is Ownable {
    /// @notice 定义账户与 DID 之间的绑定状态。
    /// @param did 绑定到该账户的 DID 字符串。
    /// @param active 该 DID 绑定是否处于激活状态。
    struct Binding {
        string did;
        bool active;
    }

    mapping(address => Binding) private _bindings;
    mapping(bytes32 => address) private _didAccounts;

    /// @notice 账户完成 DID 绑定时触发。
    /// @param account 被绑定 DID 的账户地址。
    /// @param did 绑定成功的 DID。
    event DidBound(address indexed account, string did);

    /// @notice DID 绑定状态发生变化时触发。
    /// @param account DID 所属账户地址。
    /// @param did 状态发生变化的 DID。
    /// @param active 更新后的激活状态。
    event DidStatusChanged(address indexed account, string did, bool active);

    /// @notice 为指定账户绑定 DID 并置为激活状态。
    /// @dev 同一个 DID 在任意时刻只能绑定到一个账户。
    /// @param account 待绑定的账户地址。
    /// @param did 待绑定的 DID 字符串。
    function bindDid(address account, string calldata did) external onlyOwner {
        require(account != address(0), "DidRegistry: account is zero");
        require(bytes(did).length != 0, "DidRegistry: empty did");

        Binding storage currentBinding = _bindings[account];
        bytes32 newDidHash = _hash(did);
        address existingAccount = _didAccounts[newDidHash];

        require(
            existingAccount == address(0) || existingAccount == account,
            "DidRegistry: did already bound"
        );

        if (bytes(currentBinding.did).length != 0) {
            delete _didAccounts[_hash(currentBinding.did)];
        }

        currentBinding.did = did;
        currentBinding.active = true;
        _didAccounts[newDidHash] = account;

        emit DidBound(account, did);
        emit DidStatusChanged(account, did, true);
    }

    /// @notice 更新既有 DID 绑定的激活状态。
    /// @param account 需要更新 DID 状态的账户地址。
    /// @param active 目标激活状态。
    function setDidStatus(address account, bool active) external onlyOwner {
        Binding storage binding = _bindings[account];
        require(bytes(binding.did).length != 0, "DidRegistry: did not found");
        binding.active = active;
        emit DidStatusChanged(account, binding.did, active);
    }

    /// @notice 返回账户当前绑定的 DID，不区分是否激活。
    /// @param account 待查询的账户地址。
    /// @return 账户绑定的 DID；若未绑定则返回空字符串。
    function getDid(address account) external view returns (string memory) {
        return _bindings[account].did;
    }

    /// @notice 返回账户当前处于激活状态的 DID。
    /// @dev 当账户未绑定 DID 或 DID 已失效时回退。
    /// @param account 待查询的账户地址。
    /// @return 账户当前激活的 DID。
    function getActiveDid(address account) external view returns (string memory) {
        Binding storage binding = _bindings[account];
        require(binding.active, "DidRegistry: inactive did");
        require(bytes(binding.did).length != 0, "DidRegistry: did not found");
        return binding.did;
    }

    /// @notice 检查指定 DID 是否存在且为激活状态。
    /// @param did 待查询的 DID。
    /// @return 若 DID 已绑定且处于激活状态则返回 true，否则返回 false。
    function isDidActive(string calldata did) external view returns (bool) {
        address account = _didAccounts[_hash(did)];
        if (account == address(0)) {
            return false;
        }
        return _bindings[account].active;
    }

    function _hash(string memory value) private pure returns (bytes32) {
        return keccak256(bytes(value));
    }
}
