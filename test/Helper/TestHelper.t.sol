// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { MyWallet } from "../../src/MyWallet.sol";
import { Counter } from "../../src/Counter.sol";
import { MyWalletFactory } from "../../src/MyWalletFactory.sol";

import { EntryPoint } from "account-abstraction/core/EntryPoint.sol";
import { MockERC721 } from "solmate/test/utils/mocks/MockERC721.sol";
import { MockERC1155 } from "solmate/test/utils/mocks/MockERC1155.sol";

/** 
* @dev we use 3 owners and at least 2 confirm to pass the multisig requirement
* @dev also 3 guardians and at least 2 of their support to recover 
* @dev only 1 address on whiteList
*/ 

contract TestHelper is Test {
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
    uint256 [] ownerKeys;
    uint256 [] guardianKeys;
    bytes32[] guardianHashes;
    address someone;
    MyWallet wallet;
    MyWalletFactory factory;
    EntryPoint entryPoint;
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

    function setUp() public virtual {
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
        entryPoint = new EntryPoint();
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

    // utilities ====================================================
    // make _n owners with INIT_BALANCE
    function setOwners(uint256 _n) internal {
        require(_n > 0, "one owner at least");
        for(uint256 i = 0; i < _n; i++){
            string memory name = string.concat("owner", vm.toString(i));
            (address owner, uint256 privateKey) = makeAddrAndKey(name);
            vm.deal(owner, INIT_BALANCE);
            owners.push(owner);
            ownerKeys.push(privateKey);
        }
    }

    function setGuardians() internal {
        for(uint256 i = 0; i < guardianNum; i++){
            string memory name = string.concat("guardian", vm.toString(i));
            (address guardian, uint256 privateKey) = makeAddrAndKey(name);
            vm.deal(guardian, INIT_BALANCE);
            guardians.push(guardian);
            guardianKeys.push(privateKey);
        }
    }

}