# MyWallet
*This is a final project for Appworks School Blockchain Program #2 and for fun*
[HackMD](https://hackmd.io/@jimboliao/HkpVqliwh)

## Description
### Purpose
現今，大部分的人還未接觸到Web3的服務，而錢包作為進入Web3世界的入口是相當重要的服務，但也是讓許多使用者望之卻步的門檻。這個專案的目的是實踐一個智能合約錢包，提供多種功能讓使用者可以更加方便且安全的徜徉在Web3的世界裡。MyWallet作為合約錢包除了可以讓你直接由EOA互動之外，也依循EIP-4337設計，讓使用者可以透過Entry Point完成交易。

### Why smart contract wallet
合約錢包可以實作很多外部帳戶(EOA)所沒辦法實現的功能，此外，在抽象帳戶的發展下，未來的帳戶應可藉由合約來做出更多方便且彈性的功能。

一些常見的合約錢包功能如:
- Multisig authorization
- Account freezing
- Account recovery
- Set transaction limits
- Create whitelists

### Account abstraction
目前使用者要和Ethereum互動必須先有一個外部帳戶，然而外部帳戶卻有許多缺點如：沒有客製化功能、帳戶內必須要有ether作為手續費等等。而帳戶抽象化就是為了解決這些問題所提出的一些解決方法。解決方式有很多種，有些要更動以太坊底層協議才能完成，如EIP-3074以及EIP-2938；而有一寫解決方案則是透過建立額外的交易系統來達成，如EIP-4337。

#### EIP-4337
在EIP-4337之下，使用者不需要有外部帳戶，他們可以用私鑰對特定的資料結構(UserOperation)簽名，再由 Bundler 將這些已簽名的資料送到Entry Point，並和使用者自己的合約帳戶互動。
![](https://hackmd.io/_uploads/rkjz67Ot2.png)
圖片來源：https://alchemy.com/blog/account-abstraction

基本流程為：
1. 依據要互動的內容準備UserOperation
2. 使用者對UserOperation簽名
3. Bundler 鏈下透過 Entry Point 驗證 UserOperation 有效
4. Bundler 透過 Entry Point 執行 UserOperation
5. Bundler 取回手續費

手續費的補償來源可能為:
1. 使用者的合約帳戶
2. 合約帳戶在EntryPoint中存的錢
3. 第三方 (paymaster)

### More information
You can refer to following resources for more details.
- [Ethereum account-abstraction](https://ethereum.org/en/roadmap/account-abstraction/) 
- [EIP-4337](https://eips.ethereum.org/EIPS/eip-4337)
- [Tutorial and explaination on Alchemy](https://www.alchemy.com/learn/account-abstraction)

## Framework
![](https://hackmd.io/_uploads/Hk3nFV_th.png)
主要的合約為`MyWallet.sol`，內部實現多簽、凍結、白名單等功能。
`MyWalletFactory.sol`則用來創建合約帳戶，透過create2幫使用這創建合約帳戶，且以UUPS proxy方式實踐，可以升級合約邏輯。



## Development
使用Foundry作為開發以及測試環境，安裝Foundry可參考[Foundry book](https://book.getfoundry.sh/getting-started/installation)
使用`forge build`建置環境

## Testing
使用`forge test`進行測試
`MyWallet.t.sol`：測試直接使用EOA和錢包互動
`MyWalletEntry.t.sol`：測試透過Entry Point和錢包互動

## Usage
MyWallet 有幾個主要功能：
1. 多簽
2. 白名單
3. 凍結
4. 社交恢復


### 多簽
創建錢包時，使用者可以設定多位錢包的 owner 以及多簽通過的門檻 `leastConfirmThreshold`

多簽流程：
![](https://hackmd.io/_uploads/S1QlgUuF2.png)
1. owner 透過`function submitTransaction(address _to,uint256 _value,bytes calldata _data)` 傳送交易資訊，成功後會取得該交易的index，該交易狀態為PENDING
2. owner 透過`confirmTransaction(uint256 _transactionIndex)` 確認執行交易，當確認次數達到通過門檻後該交易狀態改為PASS，但若是沒有在一天內達到門檻，交易狀態改為OVERTIME，無法被執行
3. 狀態為 PASS 的交易，任何人都可以透過 `function executeTransaction(uint256 _transactionIndex) ` 執行

### 白名單
創建錢包時，使用者可以設定白名單地址，也可以在通過多簽門檻後新增或移除白名單地址。當`submitTransaction`的互動對象為白名單地址時，僅需一次confirm該交易狀態就會改成PASS。

新增、移除白名單須提交交易，設定互動對象為合約地址本身，並執行
`function addWhiteList(address _whiteAddr)`、`function removeWhiteList(address _removeAddr)`。也就是說新增或是移除白名單都需要通過多簽門檻。

### 凍結
owner 可以透過 `function freezeWallet()` 來凍結合約錢包，錢包凍結期間沒辦法執行 `function executeTransaction(uint256 _transactionIndex)`

owner 可以透過 `function unfreezeWallet()` 來解凍錢包，當多個owner (同樣以`leastConfirmThreshold` 作為門檻)執行後，錢包就會解除凍結狀態。

### 社交恢復
創建錢包時，使用者可以設定多個地址作為guardian，但MyWallet中存的是這些地址的雜湊值，用以保障守護者的隱私，取得雜湊的方式為`keccak256(abi.encodePacked(guardianAddress))`。同時設定社交恢復的門檻：`recoverThreshold`
(idea inspired by https://github.com/verumlotus/social-recovery-wallet)

社交恢復流程：
1. guardian 透過`function submitRecovery(address _replacedOwner,address _newOwner)` 傳送恢復資訊。
2. guardian 透過`function supportRecovery()`
3. 當足夠多的guardiany做完第二步達到`recoverThreshold`門檻後，owner 可以透過 `function executeRecovery()` 進行恢復

owner 可以透過`function replaceGuardian(bytes32 _oldGuardianHash, bytes32 _newGuardianHash)`替換 guardian，流程與類似新增白名單，owner 需要提交交易資訊並且通過多簽門檻。
