// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/MyWallet.sol";
import "../src/Counter.sol";

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
    address[] owners;
    address[] guardians;
    address[] whiteList;
    address someone;
    MyWallet wallet;
    Counter counter;

    event ConfirmTransaction(address indexed sender, uint256 indexed transactionIndex);
    event ExecuteTransaction(uint256 indexed transactionIndex);
    event Receive(address indexed sender, uint256 indexed amount, uint256 indexed balance);
    event SubmitRecovery(uint256 indexed replacedOwnerIndex, address indexed newOwner, address proposer);

    function setUp() public {
        setOwners(ownerNum);
        setGuardians();
        bytes32[] memory hashes = new bytes32[](guardianNum);
        for(uint256 i = 0; i < guardianNum; i++) {
            hashes[i] = keccak256(abi.encodePacked(guardians[i]));
        }
        address whiteAddr = makeAddr("whiteAddr");
        someone = makeAddr("someone");
        vm.deal(someone, INIT_BALANCE);
        whiteList.push(whiteAddr);
        wallet = new MyWallet(owners, confirmThreshold, hashes, recoverThreshold, whiteList);
        counter = new Counter();
        assertEq(wallet.leastConfirmThreshold(), confirmThreshold);
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
        require(status == MyWallet.TransactionStatus.PENDING, "status error");
        assertEq(to, address(counter));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(confirmNum, 1);
        assertEq(timestamp, block.timestamp);
        assertTrue(wallet.isConfirmed(id, owners[0]));
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
        require(status == MyWallet.TransactionStatus.PASS, "status error");
        assertEq(to, address(counter));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(confirmNum, 2);
        assertEq(timestamp, block.timestamp);
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

        // overtime
        skip(1 days + 1);

        // check effects
        assertEq(id, 0);
        (MyWallet.TransactionStatus status, , , , , ) = wallet.getTransactionInfo(id);
        require(status == MyWallet.TransactionStatus.OVERTIME, "status error");
    }

    function testSubmitTransactionToWhiteListAndExecute() public{
        // submit a transaction
        uint256 amount = 1 ether;
        vm.startPrank(owners[0]);
        (bytes memory data, uint256 id) = submitTxWhiteList(amount);
        vm.stopPrank();

        // check effects
        assertEq(id, 0);
        (MyWallet.TransactionStatus status, 
        address to, 
        uint256 value, 
        bytes memory _data, 
        uint256 confirmNum, 
        uint256 timestamp) = wallet.getTransactionInfo(id);
        require(status == MyWallet.TransactionStatus.PASS, "status error");
        assertEq(to, whiteList[0]);
        assertEq(value, amount);
        assertEq(data, _data);
        assertEq(confirmNum, 1);
        assertEq(timestamp, block.timestamp);
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
        address newOwner = makeAddr("newOwner");
        uint256 replacedOwnerIndex = 2;
        vm.prank(guardians[0]);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit SubmitRecovery(replacedOwnerIndex, newOwner, guardians[0]);
        wallet.submitRecovery(replacedOwnerIndex, newOwner);

        // check effects
        (uint256 idx, address addr, uint256 num) = wallet.getRecoveryInfo();
        assertEq(idx, replacedOwnerIndex);
        assertEq(addr, newOwner);
        assertEq(num, 0);
        assertTrue(wallet.isRecovering());
    }

    function testSupportRecovery() public {
        // submit recovery
        address newOwner = makeAddr("newOwner");
        uint256 replacedOwnerIndex = 2;
        vm.prank(guardians[0]);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit SubmitRecovery(replacedOwnerIndex, newOwner, guardians[0]);
        wallet.submitRecovery(replacedOwnerIndex, newOwner);

        // support recovery
        vm.prank(guardians[0]);
        wallet.supportRecovery();

        // check effects
        (, , uint256 num) = wallet.getRecoveryInfo();
        assertEq(num, 1);
        assertTrue(wallet.recoverBy(0, guardians[0]));
    }

    function testExecuteRecovery() public {
        // submit recovery
        address newOwner = makeAddr("newOwner");
        uint256 replacedOwnerIndex = 2;
        vm.prank(guardians[0]);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit SubmitRecovery(replacedOwnerIndex, newOwner, guardians[0]);
        wallet.submitRecovery(replacedOwnerIndex, newOwner);

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
        assertFalse(wallet.isOwner(owners[replacedOwnerIndex]));
        assertFalse(wallet.isRecovering());
        assertEq(wallet.recoverRound(), 1);
        (uint256 idx, address addr, uint256 num) = wallet.getRecoveryInfo();
        assertEq(idx, 0);
        assertEq(addr, address(0));
        assertEq(num, 0);
    }

    // useful utilities 
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
}