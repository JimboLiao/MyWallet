# MyWallet
*This is a final project for Appworks School Blockchain Program #2 and for fun*

[HackMD](https://hackmd.io/@jimboliao/HkpVqliwh)

## Description
### Purpose
現今，大部分的人還未接觸到 Web3 的服務，而錢包作為進入 Web3 世界的入口是相當重要的服務，但也是讓許多使用者望之卻步的門檻。這個專案的目的是實踐一個智能合約錢包，提供多種功能讓使用者可以更加方便且安全的徜徉在 Web3 的世界裡。MyWallet 作為合約錢包除了可以讓你直接由 EOA 互動之外，也依循 EIP-4337 設計，讓使用者可以透過 EntryPoint 完成交易。

### Why smart contract wallet
合約錢包可以實作很多外部帳戶 (EOA) 所沒辦法實現的功能，此外，在抽象帳戶的發展下，未來的帳戶應可藉由合約來做出更多方便且彈性的功能。

一些常見的合約錢包功能如:
- Multisig authorization
- Account freezing
- Account recovery
- Set transaction limits
- Create whitelists

### Account abstraction
目前使用者要和 Ethereum 互動必須先有一個外部帳戶，然而外部帳戶卻有許多缺點如：沒有客製化功能、帳戶內必須要有 ether 作為手續費等等。而帳戶抽象化就是為了解決這些問題所提出的一些解決方法。解決方式有很多種，有些要更動以太坊底層協議才能完成，如 EIP-3074 以及 EIP-2938 ；而有一些解決方案則是透過建立額外的交易系統來達成，如 EIP-4337 。

#### EIP-4337
在 EIP-4337 之下，使用者不需要有外部帳戶，他們僅需準備想要互動的資料包裝成 UserOperation，再由 Bundler 將資料送到 EntryPoint，並和使用者自己的合約帳戶互動，合約帳戶內應自行定義驗證該 UserOperation 有沒有權限的方法。
![](https://hackmd.io/_uploads/rkjz67Ot2.png)
圖片來源：https://alchemy.com/blog/account-abstraction

基本流程為：
1. user 依據要互動的內容準備 UserOperation
2. user 將 UserOperation 發送到池中
3. Bundler 鏈下透過 EntryPoint 驗證 UserOperation 有效
    - `simulateValidation(UserOperation calldata userOp)`
5. 將有效的一堆 UserOperation 包起來送到 EntryPoint 執行 
    - `handleOps(UserOperation[] calldata ops, address payable beneficiary)`
7. Bundler 取回手續費和獎勵

手續費的補償來源可能為:
1. 使用者的合約帳戶
2. 合約帳戶在 EntryPoint 中存的錢
3. 第三方 (paymaster)

### More information
You can refer to following resources for more details.
- [Ethereum account-abstraction](https://ethereum.org/en/roadmap/account-abstraction/) 
- [EIP-4337](https://eips.ethereum.org/EIPS/eip-4337)
- [Tutorial and explaination on Alchemy](https://www.alchemy.com/learn/account-abstraction)

## Framework
![](https://hackmd.io/_uploads/Hk3nFV_th.png)
主要的合約為 `MyWallet.sol` ，內部實現多簽、凍結、白名單等功能。
`MyWalletFactory.sol` 則用來創建合約帳戶，透過create2幫使用這創建合約帳戶，且以 UUPS proxy 方式實踐，可以升級合約邏輯。


## Development
使用Foundry作為開發以及測試環境，安裝Foundry可參考[Foundry book](https://book.getfoundry.sh/getting-started/installation)

clone repo:
`git clone https://github.com/JimboLiao/MyWallet.git`

使用`forge build`建置環境

## Testing
使用`forge test`進行測試
- `MyWallet.t.sol`：測試直接使用EOA和錢包互動
- `MyWalletEntry.t.sol`：測試透過Entry Point和錢包互動
- `MyWalletWithPayMaster.t.sol`：測試使用以 ERC20 和 PayMaster 支付手續費

## Usage
MyWallet 有以下幾個主要功能：
1. 多簽
2. 白名單
3. 凍結
4. 社交恢復
5. EIP-4337 驗證 UserOperation


### 多簽 ＭultiSig
創建錢包時，使用者可以設定多位錢包的 owner 以及多簽通過的門檻 `leastConfirmThreshold`

多簽流程：
![](https://hackmd.io/_uploads/SkY_rgnK2.png)
1. owner 透過`function submitTransaction(address _to,uint256 _value,bytes calldata _data)` 傳送交易資訊，成功後會取得該交易的index，該交易狀態為PENDING
2. owner 透過`confirmTransaction(uint256 _transactionIndex)` 確認執行交易，當確認次數達到通過門檻後該交易狀態改為 PASS，但若是沒有在一天內達到門檻，交易狀態改為 OVERTIME，無法被執行
3. 狀態為 PASS 的交易，任何人都可以透過 `function executeTransaction(uint256 _transactionIndex) ` 執行

### 白名單 WhiteList
創建錢包時，使用者可以設定白名單地址，也可以在通過多簽門檻後新增或移除白名單地址。當 `submitTransaction` 的互動對象為白名單地址時，僅需一次 confirm 該交易狀態就會改成PASS。

新增、移除白名單：
![](https://hackmd.io/_uploads/rJGAFl2Y2.png)
新增、移除白名單須提交交易，設定互動對象為合約地址本身，並執行
`function addWhiteList(address _whiteAddr)`、`function removeWhiteList(address _removeAddr)`。也就是說新增或是移除白名單都需要通過多簽門檻。


### 凍結 Freeze
owner 可以透過 `function freezeWallet()` 來凍結合約錢包，錢包凍結期間沒辦法執行 `function executeTransaction(uint256 _transactionIndex)`

owner 可以透過 `function unfreezeWallet()` 來解凍錢包，當多個owner (同樣以`leastConfirmThreshold` 作為門檻)執行後，錢包就會解除凍結狀態。

凍結、解凍：
![](https://hackmd.io/_uploads/rker9lnYh.png)

### 社交恢復 Social Recovery
創建錢包時，使用者可以設定多個地址作為 guardian，但 MyWallet 中存的是這些地址的雜湊值，用以保障守護者的隱私，取得雜湊的方式為`keccak256(abi.encodePacked(guardianAddress))`。
(idea inspired by https://github.com/verumlotus/social-recovery-wallet)

類似於多簽，要完成恢復需要達成另一個門檻 `recoverThreshold` ，至少需有這麼多的 guardian 支持才能真的執行社交恢復。

社交恢復流程：
![](https://hackmd.io/_uploads/rkUwCe3Yh.png)
1. guardian 透過 `function submitRecovery(address _replacedOwner,address _newOwner)` 傳送恢復資訊。
2. guardian 透過`function supportRecovery()`
3. 當足夠多的 guardian 做完第二步達到 `recoverThreshold` 門檻後，owner 可以透過 `function executeRecovery()` 進行恢復

![](https://hackmd.io/_uploads/rJ2zJb3K2.png)
owner 可以透過`function replaceGuardian(bytes32 _oldGuardianHash, bytes32 _newGuardianHash)`替換 guardian，流程與類似新增白名單，owner 需要提交交易資訊並且通過多簽門檻。

### EIP-4337 驗證 UserOperation
MyWallet 仍然以 ECDSA 的簽名方法驗證，當 signer 為 owner / guardian 時驗證才通過。