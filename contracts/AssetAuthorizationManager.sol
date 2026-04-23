// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

import "./AssetOperatorBase.sol";

contract AssetAuthorizationManager is AssetOperatorBase {
    /// @dev 资产处于正常状态时的状态码，与 AssetDirectory 中的约定保持一致。
    uint8 private constant ASSET_STATUS_NORMAL = 0;

    /// @dev 记录一笔待被授权方响应的授权请求。
    /// @param ownerDid 发起授权请求时，授权方账户绑定的激活 DID 快照。
    /// @param granteeDid 被授权方在收到请求时绑定的激活 DID 快照。
    /// @param requestTime 授权请求进入待响应状态的区块时间戳。
    /// @param exists 标识该请求当前是否仍处于待响应状态。
    struct AuthorizationRequest {
        string ownerDid;
        string granteeDid;
        uint256 requestTime;
        bool exists;
    }

    /// @dev 按资产键与被授权账户地址索引待响应的授权请求。
    ///      这里以账户地址而不是 DID 作为索引，便于被授权账户直接响应，
    ///      同时通过结构体中的 DID 快照校验响应时身份是否发生变化。
    mapping(bytes32 => mapping(address => AuthorizationRequest)) private _authorizationRequests;

    /// @notice 资产授权请求发起时触发。
    /// @param assetKey 资产标识的哈希键。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起请求时的资产所有者 DID。
    /// @param granteeDid 被请求授权的 DID。
    /// @param metadata 资产授权元数据，采用 JSON 字符串格式
    /// @param requester 发起授权请求的链上账户。
    /// @param requestTime 授权请求创建时的区块时间戳。
    event AssetAuthorizationRequested(
        bytes32 indexed assetKey,
        string assetId,
        string ownerDid,
        string granteeDid,
        string metadata,
        address indexed requester,
        uint256 requestTime
    );

    /// @notice 资产授权成功时触发。
    /// @param assetKey 资产标识的哈希键。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起授权的资产所有者 DID。
    /// @param granteeDid 被授权的 DID。
    /// @param operator 触发最终授权落库的链上账户，即接受请求的被授权方账户。
    /// @param grantTime 授权发生时的区块时间戳。
    event AssetAuthorizationGranted(
        bytes32 indexed assetKey,
        string assetId,
        string ownerDid,
        string granteeDid,
        address indexed operator,
        uint256 grantTime
    );

    /// @notice 资产授权请求被拒绝时触发。
    /// @param assetKey 资产标识的哈希键。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起请求的资产所有者 DID。
    /// @param granteeDid 拒绝请求的 DID。
    /// @param operator 发起拒绝交易的链上账户。
    /// @param rejectTime 拒绝发生时的区块时间戳。
    event AssetAuthorizationRejected(
        bytes32 indexed assetKey,
        string assetId,
        string ownerDid,
        string granteeDid,
        address indexed operator,
        uint256 rejectTime
    );

    /// @notice 资产授权被撤销时触发。
    /// @param assetKey 资产标识的哈希键。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起撤销的资产所有者 DID。
    /// @param granteeDid 被撤销授权的 DID。
    /// @param operator 发起撤销交易的链上账户。
    /// @param revokeTime 撤销发生时的区块时间戳。
    event AssetAuthorizationRevoked(
        bytes32 indexed assetKey,
        string assetId,
        string ownerDid,
        string granteeDid,
        address indexed operator,
        uint256 revokeTime
    );

    constructor(address directoryAddress, address didRegistryAddress)
        public
        AssetOperatorBase(directoryAddress, didRegistryAddress)
    {}

    /// @notice 向其他账户发起资产授权请求，等待被授权方确认。
    /// @dev 本函数不直接写入最终授权，而是先记录一笔待响应请求。
    ///      真正的授权仅会在被授权方调用 acceptAuthorizationRequest 后落库。
    /// @param assetId 资产唯一业务标识。
    /// @param granteeAccount 被请求授权的账户，其当前激活 DID 将成为请求目标。
    /// @param metadata 资产授权元数据，采用 JSON 字符串格式
    function grantAuthorization(string calldata assetId, address granteeAccount, string calldata metadata) external {
        require(granteeAccount != address(0), "AssetAuthorizationManager: zero account");

        bytes32 assetKey = keccak256(bytes(assetId));
        string memory ownerDid = _resolveActiveDid(msg.sender);
        string memory granteeDid = _resolveActiveDid(granteeAccount);
        AuthorizationRequest storage request = _authorizationRequests[assetKey][granteeAccount];

        // 在创建待响应请求之前，先确认资产当前确实可被该所有者发起授权，
        // 避免无效请求进入队列并把失败推迟到被授权方响应时才暴露。
        _validateAuthorizationRequest(assetId, ownerDid, granteeDid);
        require(!request.exists, "AssetAuthorizationManager: request already pending");

        request.ownerDid = ownerDid;
        request.granteeDid = granteeDid;
        request.requestTime = block.timestamp;
        request.exists = true;

        emit AssetAuthorizationRequested(
            assetKey,
            assetId,
            ownerDid,
            granteeDid,
            metadata,
            msg.sender,
            block.timestamp
        );
    }

    /// @notice 接受当前账户收到的资产授权请求，并执行真正的授权写入。
    /// @dev 仅请求指定的被授权账户可以接受请求，且接受时其激活 DID 必须与收到请求时一致，
    ///      从而避免账户在切换 DID 后误把旧请求授权给新的身份。
    /// @param assetId 资产唯一业务标识。
    function acceptAuthorizationRequest(string calldata assetId) external {
        bytes32 assetKey = keccak256(bytes(assetId));
        AuthorizationRequest storage request = _requireAuthorizationRequest(assetKey, msg.sender);
        string memory currentGranteeDid = _resolveActiveDid(msg.sender);

        require(
            _sameString(currentGranteeDid, request.granteeDid),
            "AssetAuthorizationManager: grantee DID changed"
        );

        // 最终授权仍由目录合约完成，以复用其对资产归属、状态和授权版本的统一校验。
        directory.grantAssetAuthorization(assetId, request.ownerDid, request.granteeDid);

        emit AssetAuthorizationGranted(
            assetKey,
            assetId,
            request.ownerDid,
            request.granteeDid,
            msg.sender,
            block.timestamp
        );

        delete _authorizationRequests[assetKey][msg.sender];
    }

    /// @notice 拒绝当前账户收到的资产授权请求。
    /// @dev 拒绝后仅清理待响应请求，不会触碰任何已生效授权。
    /// @param assetId 资产唯一业务标识。
    function rejectAuthorizationRequest(string calldata assetId) external {
        bytes32 assetKey = keccak256(bytes(assetId));
        AuthorizationRequest storage request = _requireAuthorizationRequest(assetKey, msg.sender);
        string memory currentGranteeDid = _resolveActiveDid(msg.sender);

        require(
            _sameString(currentGranteeDid, request.granteeDid),
            "AssetAuthorizationManager: grantee DID changed"
        );

        emit AssetAuthorizationRejected(
            assetKey,
            assetId,
            request.ownerDid,
            request.granteeDid,
            msg.sender,
            block.timestamp
        );

        delete _authorizationRequests[assetKey][msg.sender];
    }

    /// @notice 撤销其他账户对应激活 DID 的资产使用权限。
    /// @param assetId 资产唯一业务标识。
    /// @param granteeAccount 被撤销授权的账户，其激活 DID 对应授权将失效。
    function revokeAuthorization(string calldata assetId, address granteeAccount) external {
        require(granteeAccount != address(0), "AssetAuthorizationManager: zero account");

        string memory ownerDid = _resolveActiveDid(msg.sender);
        string memory granteeDid = _resolveActiveDid(granteeAccount);

        directory.revokeAssetAuthorization(assetId, ownerDid, granteeDid);

        emit AssetAuthorizationRevoked(
            keccak256(bytes(assetId)),
            assetId,
            ownerDid,
            granteeDid,
            msg.sender,
            block.timestamp
        );
    }

    /// @notice 查询指定账户当前是否存在待响应的资产授权请求。
    /// @param assetId 资产唯一业务标识。
    /// @param granteeAccount 被请求授权的账户地址。
    /// @return pending 是否存在待响应请求。
    /// @return ownerDid 发起请求时记录的资产所有者 DID。
    /// @return granteeDid 请求目标 DID。
    /// @return requestTime 请求创建时的区块时间戳。
    function getAuthorizationRequest(
        string calldata assetId,
        address granteeAccount
    )
        external
        view
        returns (
            bool pending,
            string memory ownerDid,
            string memory granteeDid,
            uint256 requestTime
        )
    {
        AuthorizationRequest storage request =
            _authorizationRequests[keccak256(bytes(assetId))][granteeAccount];
        return (
            request.exists,
            request.ownerDid,
            request.granteeDid,
            request.requestTime
        );
    }

    /// @dev 读取并校验待响应授权请求是否存在。
    /// @param assetKey 资产标识的哈希键。
    /// @param granteeAccount 被授权账户地址。
    /// @return request 对应的待响应授权请求存储引用。
    function _requireAuthorizationRequest(
        bytes32 assetKey,
        address granteeAccount
    ) private view returns (AuthorizationRequest storage request) {
        request = _authorizationRequests[assetKey][granteeAccount];
        require(request.exists, "AssetAuthorizationManager: request not found");
    }

    /// @dev 在写入待响应请求前校验资产是否允许当前所有者发起授权。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 授权方当前激活 DID。
    /// @param granteeDid 被授权方当前激活 DID。
    function _validateAuthorizationRequest(
        string calldata assetId,
        string memory ownerDid,
        string memory granteeDid
    ) private view {
        require(
            directory.getAssetStatus(assetId) == ASSET_STATUS_NORMAL,
            "AssetDirectory: asset not authorizable"
        );
        require(
            _sameString(directory.getAssetOwner(assetId), ownerDid),
            "AssetDirectory: owner mismatch"
        );
        require(!_sameString(ownerDid, granteeDid), "AssetDirectory: self authorization");
        require(
            !directory.isAssetAuthorized(assetId, granteeDid),
            "AssetAuthorizationManager: authorization already active"
        );
    }

    /// @dev 使用 keccak256 对字符串做等值比较，兼容 Solidity 0.6 对 string 的限制。
    /// @param left 左侧字符串。
    /// @param right 右侧字符串。
    /// @return 若两个字符串内容一致则返回 true。
    function _sameString(string memory left, string memory right) private pure returns (bool) {
        return keccak256(bytes(left)) == keccak256(bytes(right));
    }
}
