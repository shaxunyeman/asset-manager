# 资产管理智能合约部署说明

## 1. 项目说明

本项目包含 5 个核心合约：

1. `DidRegistry`
   用于维护链上账户地址与 DID 的绑定关系。
2. `AssetDirectory`
   资产目录中心存储合约，保存资产信息、授权状态以及三个业务管理合约地址。
3. `AssetRegistrationManager`
   资产注册合约，负责新增资产。
4. `OwnershipTransferManager`
   权属转移合约，负责资产所有权转移。
5. `AssetAuthorizationManager`
   授权管理合约，负责资产授权与撤销授权。

其中，`AssetDirectory` 是唯一的资产目录表存储入口，三个业务合约分别通过受控接口对目录表进行操作。

## 2. 环境要求

部署前请确认本机环境满足以下条件：

1. Node.js 版本建议不低于 `18`，当前工程已在 `Node.js v20` 下验证。
2. NPM 可正常使用。
3. Solidity 编译器版本固定为 `0.6.10`。
4. 已安装当前工程依赖。

安装依赖命令如下：

```bash
npm install
```

编译命令如下：

```bash
npm run compile
```

测试命令如下：

```bash
npm test
```

## 3. 部署前需要理解的关系

部署顺序不能颠倒，原因如下：

1. 三个业务合约在构造时都依赖 `AssetDirectory` 和 `DidRegistry` 的地址。
2. `AssetDirectory` 部署完成后，还需要由所有者设置三个业务合约地址。
3. 业务账户在发起资产注册、转移、授权之前，必须先在 `DidRegistry` 中完成 DID 绑定。

推荐的部署顺序如下：

1. 部署 `DidRegistry`
2. 部署 `AssetDirectory`
3. 部署 `AssetRegistrationManager`
4. 部署 `OwnershipTransferManager`
5. 部署 `AssetAuthorizationManager`
6. 调用 `AssetDirectory` 的管理函数，注册三个业务合约地址
7. 调用 `DidRegistry` 为业务账户绑定 DID

## 4. 本地开发网络部署步骤

### 4.1 启动 Hardhat 本地链

打开一个终端执行：

```bash
npx hardhat node
```

启动后，Hardhat 会输出一组测试账户及私钥，并监听本地地址：

```text
http://127.0.0.1:8545
```

### 4.2 打开 Hardhat Console

新开一个终端，在项目根目录执行：

```bash
npx hardhat console --network localhost
```

以下部署命令均在该控制台中执行。

### 4.3 部署 `DidRegistry`

```javascript
const DidRegistry = await ethers.getContractFactory("DidRegistry");
const didRegistry = await DidRegistry.deploy();
await didRegistry.deployed();
didRegistry.address
```

记录输出的 `didRegistry.address`。

### 4.4 部署 `AssetDirectory`

```javascript
const AssetDirectory = await ethers.getContractFactory("AssetDirectory");
const assetDirectory = await AssetDirectory.deploy();
await assetDirectory.deployed();
assetDirectory.address
```

记录输出的 `assetDirectory.address`。

### 4.5 部署 `AssetRegistrationManager`

```javascript
const AssetRegistrationManager = await ethers.getContractFactory("AssetRegistrationManager");
const registrationManager = await AssetRegistrationManager.deploy(
  assetDirectory.address,
  didRegistry.address
);
await registrationManager.deployed();
registrationManager.address
```

### 4.6 部署 `OwnershipTransferManager`

```javascript
const OwnershipTransferManager = await ethers.getContractFactory("OwnershipTransferManager");
const transferManager = await OwnershipTransferManager.deploy(
  assetDirectory.address,
  didRegistry.address
);
await transferManager.deployed();
transferManager.address
```

### 4.7 部署 `AssetAuthorizationManager`

```javascript
const AssetAuthorizationManager = await ethers.getContractFactory("AssetAuthorizationManager");
const authorizationManager = await AssetAuthorizationManager.deploy(
  assetDirectory.address,
  didRegistry.address
);
await authorizationManager.deployed();
authorizationManager.address
```

## 5. 部署后的初始化步骤

### 5.1 在 `AssetDirectory` 中登记三个业务合约

`AssetDirectory` 默认由部署者持有所有权，因此以下操作需要由部署账户执行。

```javascript
await assetDirectory.setRegistrationManager(registrationManager.address);
await assetDirectory.setTransferManager(transferManager.address);
await assetDirectory.setAuthorizationManager(authorizationManager.address);
```

可通过以下命令检查配置结果：

```javascript
await assetDirectory.registrationManager();
await assetDirectory.transferManager();
await assetDirectory.authorizationManager();
```

### 5.2 在 `DidRegistry` 中为业务账户绑定 DID

下面以 Hardhat 默认账户举例：

```javascript
const [deployer, alice, bob, carol] = await ethers.getSigners();
```

为相关账户绑定 DID：

```javascript
await didRegistry.bindDid(alice.address, "did:example:alice");
await didRegistry.bindDid(bob.address, "did:example:bob");
await didRegistry.bindDid(carol.address, "did:example:carol");
```

检查 DID 是否绑定成功：

```javascript
await didRegistry.getDid(alice.address);
await didRegistry.getActiveDid(alice.address);
await didRegistry.isDidActive("did:example:alice");
```

## 6. 业务调用示例

### 6.1 注册资产

由 `alice` 发起资产注册：

```javascript
await registrationManager
  .connect(alice)
  .registerAsset("asset-001", "{\"name\":\"device-1\",\"type\":\"equipment\"}");
```

查询资产信息：

```javascript
await assetDirectory.getAsset("asset-001");
await assetDirectory.getAssetOwner("asset-001");
await assetDirectory.getAssetStatus("asset-001");
```

### 6.2 资产授权

由资产所有者 `alice` 将资产授权给 `bob`：

```javascript
await authorizationManager
  .connect(alice)
  .grantAuthorization("asset-001", bob.address);
```

查询授权状态：

```javascript
await assetDirectory.isAssetAuthorized("asset-001", "did:example:bob");
await assetDirectory.getAuthorizationState("asset-001", "did:example:bob");
```

撤销授权：

```javascript
await authorizationManager
  .connect(alice)
  .revokeAuthorization("asset-001", bob.address);
```

### 6.3 资产权属转移

由 `alice` 将资产转移给 `carol`：

```javascript
await transferManager
  .connect(alice)
  .transferAssetOwnership("asset-001", carol.address);
```

转移完成后再查询资产所有者：

```javascript
await assetDirectory.getAssetOwner("asset-001");
```

说明：

1. 权属转移后，旧授权会自动失效。
2. 若资产状态不是“正常”，则不能进行转移或授权。

## 7. 资产状态管理

`AssetDirectory` 的所有者可以直接调整资产状态：

```javascript
await assetDirectory.setAssetStatus("asset-001", 1);
```

状态说明如下：

1. `0`：正常
2. `1`：冻结
3. `2`：报废

注意事项：

1. 当资产状态变为 `冻结` 或 `报废` 时，既有授权会整体失效。
2. 冻结或报废状态下，不允许继续授权，也不允许执行权属转移。

## 8. 生产环境部署建议

若部署到测试网、联盟链或生产链，建议按以下方式执行：

1. 使用专门的部署账户部署 `DidRegistry` 和 `AssetDirectory`。
2. 部署完成后，立即记录 5 个核心合约地址，并归档到配置中心或交付文档。
3. 使用多签账户或治理账户接管 `DidRegistry` 和 `AssetDirectory` 的所有权，避免长期由个人账户持有高权限。
4. 对 DID 绑定流程建立运维审批机制，避免错误绑定造成资产权属风险。
5. 将合约地址、初始化交易哈希、部署区块高度、编译器版本、源码版本号统一留档。
6. 正式环境建议补充独立部署脚本，不建议长期依赖手工 console 部署。

## 9. 常见问题

### 9.1 为什么资产所有者用 DID，而不是链上地址

因为题目要求 `owner` 使用 DID 标识。为了解决链上调用者身份校验问题，项目额外引入了 `DidRegistry`，通过“地址 -> DID”的绑定关系，将链上账户与业务身份关联起来。

### 9.2 为什么有三个业务合约，而不是把所有逻辑写到一个合约里

这样做的目的主要有三点：

1. 职责边界清晰，便于审计。
2. 权限模型更清楚，不同操作由不同入口负责。
3. 后续若需要升级某类业务入口，不必直接改动资产目录存储结构。

### 9.3 如何确认部署成功

至少应验证以下几点：

1. 五个核心合约都已成功部署并返回地址。
2. `AssetDirectory` 中三个管理合约地址已设置成功。
3. `DidRegistry` 能正确返回测试账户绑定的 DID。
4. 能完成一次完整业务链路：注册资产、授权资产、撤销授权、转移权属。
5. `npm test` 通过。

## 10. 当前工程中可直接使用的命令

```bash
npm install
npm run compile
npm test
npx hardhat node
npx hardhat console --network localhost
```
