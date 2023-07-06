// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/MyWallet.sol";
import "../src/Counter.sol";
import "../src/MyWalletFactory.sol";

import { MockERC721 } from "solmate/test/utils/mocks/MockERC721.sol";
import { MockERC1155 } from "solmate/test/utils/mocks/MockERC1155.sol";

/** 
* @dev In this test, we use 3 owners and at least 2 confirm to pass the multisig requirement
* @dev also 3 guardians and at least 2 of their support to recover 
* @dev only 1 address on whiteList
*/ 

contract MyWalletTest is Test {
    uint256 constant INIT_BALANCE = 100 ether;
    uint256 constant ownerNum = 3;
    uint256 constant confirmThreshold = 2;
    uint256 constant guardianNum = 3;
    uint256 constant recoverThreshold = 2;
    uint256 constant timeLimit = 1 days;
    uint256 constant salt = 1;
    address[] owners;
    address[] guardians;
    address[] whiteList;
    bytes32[] guardianHashes;
    address someone;
    MyWallet wallet;
    MyWalletFactory factory;
    Counter counter;
    MockERC721 mockErc721;
    MockERC1155 mockErc1155;

    event SubmitTransaction(address indexed sender, uint256 indexed transactionIndex);
    event ConfirmTransaction(address indexed sender, uint256 indexed transactionIndex);
    event TransactionPassed(uint256 indexed transactionIndex);
    event ExecuteTransaction(uint256 indexed transactionIndex);
    event Receive(address indexed sender, uint256 indexed amount, uint256 indexed balance);
    event SubmitRecovery(address indexed replacedOwner, address indexed newOwner, address proposer);
    event ExecuteRecovery(address indexed oldOwner, address indexed newOwner);
    event AddNewWhiteList(address indexed whiteAddr);
    event RemoveWhiteList(address indexed removeAddr);
    event ReplaceGuardian(bytes32 indexed oldGuardianHash, bytes32 indexed newGuardianHash);
    event FreezeWallet();
    event UnfreezeWallet();

    function setUp() public {
        // setting MyWallet
        setOwners(ownerNum);
        setGuardians();
        for(uint256 i = 0; i < guardianNum; i++) {
            guardianHashes.push(keccak256(abi.encodePacked(guardians[i])));
        }
        address whiteAddr = makeAddr("whiteAddr");
        someone = makeAddr("someone");
        vm.deal(someone, INIT_BALANCE);
        whiteList.push(whiteAddr);
        factory = new MyWalletFactory();
        wallet = factory.createAccount(owners, confirmThreshold, guardianHashes, recoverThreshold, whiteList, salt);
        assertEq(wallet.leastConfirmThreshold(), confirmThreshold);

        // setting test contracts
        counter = new Counter();
        mockErc721 = new MockERC721("MockERC721", "MERC721");
        mockErc1155 = new MockERC1155();

        vm.label(address(wallet), "MyWallet");
        vm.label(address(counter), "counter");
        vm.label(address(mockErc721), "mockERC721");
        vm.label(address(mockErc1155), "mockERC1155");
    }

    function testReceive() public {
        uint256 amount = 1 ether;
        vm.startPrank(someone);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit Receive(someone, amount, amount);
        payable(address(wallet)).transfer(amount);
        vm.stopPrank();

        // check effects
        assertEq(address(wallet).balance, amount);
        assertEq(someone.balance, INIT_BALANCE - amount);
    }

    function testSubmitTransaction() public {
        // submit a transaction
        vm.startPrank(owners[0]);
        (bytes memory data, uint256 id) = submitTx();
        vm.stopPrank();

        // check effects
        assertEq(id, 0);
        (MyWallet.TransactionStatus status, 
        address to, 
        uint256 value, 
        bytes memory _data, 
        uint256 confirmNum, 
        uint256 timestamp) = wallet.getTransactionInfo(id);
        require(status == MyWalletStorage.TransactionStatus.PENDING, "status error");
        assertEq(to, address(counter));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(confirmNum, 0);
        assertEq(timestamp, block.timestamp + timeLimit);
    }

    function testSubmitBySomeone() public {
        // submit a transaction
        vm.startPrank(someone);
        vm.expectRevert(MyWallet.NotOwner.selector);
        submitTx();
        vm.stopPrank();

    }

    function testConfirmTransaction() public {
        // submit a transaction
        vm.startPrank(owners[0]);
        (bytes memory data, uint256 id) = submitTx();
        // owners[0] confirm the transaction
        vm.expectEmit(true, true, true, true, address(wallet));
        emit ConfirmTransaction(address(owners[0]), id);
        wallet.confirmTransaction(id);
        vm.stopPrank();
        // owners[1] confirm the transaction
        vm.startPrank(owners[1]);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit ConfirmTransaction(address(owners[1]), id);
        wallet.confirmTransaction(id);
        vm.stopPrank();
        
        // check effects
        (MyWallet.TransactionStatus status, 
        address to, 
        uint256 value, 
        bytes memory _data, 
        uint256 confirmNum, 
        uint256 timestamp) = wallet.getTransactionInfo(id);
        // status should be PASS after 2 confirm
        require(status == MyWalletStorage.TransactionStatus.PASS, "status error");
        assertEq(to, address(counter));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(confirmNum, 2);
        assertEq(timestamp, block.timestamp + timeLimit);
        assertTrue(wallet.isConfirmed(id, owners[0]));
        assertTrue(wallet.isConfirmed(id, owners[1]));
    }

    function testConfirmBySomeone() public {
        // submit a transaction
        vm.startPrank(owners[0]);
        (, uint256 id) = submitTx();
        vm.stopPrank();

        // someone confirm the transaction
        vm.startPrank(someone);
        vm.expectRevert(MyWallet.NotOwner.selector);
        wallet.confirmTransaction(id);
        vm.stopPrank();
    }

    function testExecuteTransaction() public {
        // submit a transaction
        vm.startPrank(owners[0]);
        (, uint256 id) = submitTx();
        // owners[0] confirm the transaction
        vm.expectEmit(true, true, true, true, address(wallet));
        emit ConfirmTransaction(address(owners[0]), id);
        wallet.confirmTransaction(id);
        vm.stopPrank();
        // owners[1] confirm the transaction
        vm.startPrank(owners[1]);
        wallet.confirmTransaction(id);
        vm.stopPrank();
        // everyone can call execute
        vm.expectEmit(true, true, true, true, address(wallet));
        emit ExecuteTransaction(id);
        wallet.executeTransaction(id);

        // check effects
        assertEq(counter.number(), 1);
    }

    function testOverTime() public {
        // submit a transaction
        vm.startPrank(owners[0]);
        (, uint256 id) = submitTx();
        vm.stopPrank();

        (MyWallet.TransactionStatus status, , , , , ) = wallet.getTransactionInfo(id);
        require(status == MyWalletStorage.TransactionStatus.PENDING, "status error");

        // overtime
        skip(1 days + 1);

        // check effects
        assertEq(id, 0);
        (status, , , , , ) = wallet.getTransactionInfo(id);
        require(status == MyWalletStorage.TransactionStatus.OVERTIME, "status error");
    }

    function testSubmitTransactionToWhiteListAndExecute() public{
        // submit a transaction
        uint256 amount = 1 ether;
        vm.startPrank(owners[0]);
        (bytes memory data, uint256 id) = submitTxWhiteList(amount);
        // owners[0] confirm the transaction
        vm.expectEmit(true, true, true, true, address(wallet));
        emit ConfirmTransaction(address(owners[0]), id);
        wallet.confirmTransaction(id);
        vm.stopPrank();

        // check effects
        assertEq(id, 0);
        (MyWallet.TransactionStatus status, 
        address to, 
        uint256 value, 
        bytes memory _data, 
        uint256 confirmNum, 
        uint256 timestamp) = wallet.getTransactionInfo(id);
        require(status == MyWalletStorage.TransactionStatus.PASS, "status error");
        assertEq(to, whiteList[0]);
        assertEq(value, amount);
        assertEq(data, _data);
        assertEq(confirmNum, 1);
        assertEq(timestamp, block.timestamp + timeLimit);
        assertTrue(wallet.isConfirmed(id, owners[0]));

        // execute the transaction
        payable(address(wallet)).transfer(amount);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit ExecuteTransaction(id);
        wallet.executeTransaction(id);

        // check effects
        assertEq(whiteList[0].balance, amount);
    }

    function testFreezeWallet() public {
        // freeze wallet
        vm.startPrank(owners[0]);
        wallet.freezeWallet();
        vm.stopPrank();

        // check effects
        assertTrue(wallet.isFreezing());
    }

    function testFreezeWalletBySomeone() public {
        // freeze wallet
        vm.startPrank(someone);
        vm.expectRevert(MyWallet.NotOwner.selector);
        wallet.freezeWallet();
        vm.stopPrank();
    }

    function testUnfreezeWallet() public {
        // freeze wallet
        vm.startPrank(owners[0]);
        wallet.freezeWallet();
        vm.stopPrank();

        // check effects
        assertTrue(wallet.isFreezing());

        // unfreeze wallet
        uint256 round = 0;
        vm.prank(owners[0]);
        wallet.unfreezeWallet();
        assertTrue(wallet.unfreezeBy(round, owners[0]));
        assertEq(wallet.unfreezeCounter(), 1);

        vm.prank(owners[1]);
        wallet.unfreezeWallet();

        // cehck effects
        assertFalse(wallet.isFreezing());
        assertEq(wallet.unfreezeRound(), round + 1);
        assertEq(wallet.unfreezeCounter(), 0);
    }

    function testSubmitRecovery() public {
        // submit recovery
        (address replacedOwner, address newOwner) = submitRecovery();

        // check effects
        (address addr1, address addr2, uint256 num) = wallet.getRecoveryInfo();
        assertEq(addr1, replacedOwner);
        assertEq(addr2, newOwner);
        assertEq(num, 0);
        assertTrue(wallet.isRecovering());
    }

    function testSupportRecovery() public {
        // submit recovery
        (address replacedOwner, address newOwner) = submitRecovery();

        // support recovery
        vm.prank(guardians[0]);
        wallet.supportRecovery();

        // check effects
        (address addr1, address addr2, uint256 num) = wallet.getRecoveryInfo();
        assertEq(addr1, replacedOwner);
        assertEq(addr2, newOwner);
        assertEq(num, 1);
        assertTrue(wallet.recoverBy(0, guardians[0]));
    }

    function testExecuteRecovery() public {
        // submit recovery
        (address replacedOwner, address newOwner) = submitRecovery();

        // support recovery
        vm.prank(guardians[0]);
        wallet.supportRecovery();
        vm.prank(guardians[1]);
        wallet.supportRecovery();
        
        // execute Recovery
        vm.prank(owners[0]);
        wallet.executeRecovery();

        // check effects
        assertTrue(wallet.isOwner(newOwner));
        assertFalse(wallet.isOwner(replacedOwner));
        assertFalse(wallet.isRecovering());
        assertEq(wallet.recoverRound(), 1);
        (address addr1, address addr2, uint256 num) = wallet.getRecoveryInfo();
        assertEq(addr1, address(0));
        assertEq(addr2, address(0));
        assertEq(num, 0);
    }

    function testErc721Receive() public {
        // someone mint erc721 and transfer to wallet
        vm.startPrank(someone);
        uint256 tokenId = 0;
        mockErc721.mint(someone, tokenId);
        mockErc721.safeTransferFrom(someone, address(wallet), tokenId);
        vm.stopPrank();

        // check effects
        assertEq(mockErc721.balanceOf(address(wallet)), 1);
    }

    function testErc1155Receive() public {
        // someone mint erc1155 and transfer to wallet
        vm.startPrank(someone);
        uint256 tokenId = 0;
        uint256 amount = 1;
        mockErc1155.mint(someone, tokenId, amount, "");
        mockErc1155.safeTransferFrom(someone, address(wallet), tokenId, amount, "");
        vm.stopPrank();

        // check effects
        assertEq(mockErc1155.balanceOf(address(wallet), tokenId), 1);
    }

    function testAddWhiteList() public {
        // submit add white list tx (add someone on white list)
        vm.startPrank(owners[0]);
        bytes memory data = abi.encodeCall(MyWallet.addWhiteList, (someone));
        uint256 id = wallet.submitTransaction(address(wallet), 0, data);
        vm.stopPrank();

        // owners[0] and owners[1] confirm transaction
        vm.prank(owners[0]);
        wallet.confirmTransaction(id);
        vm.prank(owners[1]);
        wallet.confirmTransaction(id);

        // execute transaction 
        wallet.executeTransaction(id);

        // check effects
        assertTrue(wallet.isWhiteList(someone));
    }

    function testRemoveWhiteList() public {
        // submit remove white list tx
        vm.startPrank(owners[0]);
        bytes memory data = abi.encodeCall(MyWallet.removeWhiteList, (whiteList[0]));
        uint256 id = wallet.submitTransaction(address(wallet), 0, data);
        vm.stopPrank();

        // owners[0] and owners[1] confirm transaction
        vm.prank(owners[0]);
        wallet.confirmTransaction(id);
        vm.prank(owners[1]);
        wallet.confirmTransaction(id);

        // execute transaction 
        wallet.executeTransaction(id);

        // check effects
        assertFalse(wallet.isWhiteList(whiteList[0]));
    }

    function testReplaceGuardian() public {
        // submit replaceGuardian tx (add someone as new guardian)
        vm.startPrank(owners[0]);
        bytes32 newGuardianHash = keccak256(abi.encodePacked(someone));
        bytes memory data = abi.encodeCall(MyWallet.replaceGuardian, (guardianHashes[0], newGuardianHash));
        uint256 id = wallet.submitTransaction(address(wallet), 0, data);
        vm.stopPrank();

        // owners[0] and owners[1] confirm transaction
        vm.prank(owners[0]);
        wallet.confirmTransaction(id);
        vm.prank(owners[1]);
        wallet.confirmTransaction(id);

        // execute transaction 
        wallet.executeTransaction(id);

        // check effects
        assertTrue(wallet.isGuardian(newGuardianHash));
        assertFalse(wallet.isGuardian(guardianHashes[0]));
    }

    // utilities ====================================================
    // make _n owners with INIT_BALANCE
    function setOwners(uint256 _n) internal {
        require(_n > 0, "one owner at least");
        for(uint256 i = 0; i < _n; i++){
            string memory name = string.concat("owner", vm.toString(i));
            address owner = makeAddr(name);
            vm.deal(owner, INIT_BALANCE);
            owners.push(owner);
        }
    }

    function setGuardians() internal {
        for(uint256 i = 0; i < guardianNum; i++){
            string memory name = string.concat("guardian", vm.toString(i));
            address guardian = makeAddr(name);
            vm.deal(guardian, INIT_BALANCE);
            guardians.push(guardian);
        }
    }

    // submit transaction to call Counter's increment function
    function submitTx() public returns(bytes memory data, uint256 id){
        data = abi.encodeCall(Counter.increment, ());
        id = wallet.submitTransaction(address(counter), 0, data);
    }

    // submit transaction to send whiteList[0] 1 ether
    function submitTxWhiteList(uint256 amount) public 
    returns(
        bytes memory data,
        uint256 id
    ){
        data = "";
        id = wallet.submitTransaction(whiteList[0], amount, data);
    }

    // submit recovery
    function submitRecovery() public returns(address replacedOwner, address newOwner){
        newOwner = makeAddr("newOwner");
        replacedOwner = owners[2];
        vm.prank(guardians[0]);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit SubmitRecovery(replacedOwner, newOwner, guardians[0]);
        wallet.submitRecovery(replacedOwner, newOwner);
    }
    //================================================================
}