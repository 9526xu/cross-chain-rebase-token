// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interface/IRebaseToken.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/LockReleaseTokenPool.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

contract CrossChainTest is Test {
    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;
    address owner;
    address alice;

    RebaseTokenPool ethSepoliaRebaseTokenPool;
    RebaseTokenPool arbSepoliaRebaseTokenPool;

    RebaseToken ethSepoliaRebaseToken;
    RebaseToken arbSepoliaRebaseToken;

    Vault vault;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    Register.NetworkDetails ethSepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");

        ethSepoliaFork = vm.createSelectFork("eth");
        arbSepoliaFork = vm.createSelectFork("arb");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        (
            ethSepoliaRebaseToken,
            ethSepoliaRebaseTokenPool,
            ethSepoliaNetworkDetails
        ) = _deployAndConfigureChain(ethSepoliaFork);

        //  deploy source chain contract
        vm.selectFork(ethSepoliaFork);
        vm.startPrank(owner);
        vault = new Vault(IRebaseToken(address(ethSepoliaRebaseToken)));
        ethSepoliaRebaseToken.grantMinterBurnerRole(address(vault));
        vm.stopPrank();

        //  deploy target chain contract
        (
            arbSepoliaRebaseToken,
            arbSepoliaRebaseTokenPool,
            arbSepoliaNetworkDetails
        ) = _deployAndConfigureChain(arbSepoliaFork);
    }

    function _deployAndConfigureChain(
        uint256 forkId
    )
        private
        returns (RebaseToken, RebaseTokenPool, Register.NetworkDetails memory)
    {
        address[] memory allowlist = new address[](0);
        uint8 localTokenDecimals = 18;
        vm.selectFork(forkId);

        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork
            .getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        RebaseToken rebaseToken = new RebaseToken();
        RebaseTokenPool rebaseTokenPool = new RebaseTokenPool(
            IERC20(address(rebaseToken)),
            localTokenDecimals,
            allowlist,
            networkDetails.rmnProxyAddress,
            networkDetails.routerAddress
        );

        rebaseToken.grantMinterBurnerRole(address(rebaseTokenPool));

        RegistryModuleOwnerCustom registryModuleOwnerCustom = RegistryModuleOwnerCustom(
                networkDetails.registryModuleOwnerCustomAddress
            );
        registryModuleOwnerCustom.registerAdminViaOwner(address(rebaseToken));

        TokenAdminRegistry tokenAdminRegistry = TokenAdminRegistry(
            networkDetails.tokenAdminRegistryAddress
        );
        tokenAdminRegistry.acceptAdminRole(address(rebaseToken));
        tokenAdminRegistry.setPool(
            address(rebaseToken),
            address(rebaseTokenPool)
        );

        vm.stopPrank();

        return (rebaseToken, rebaseTokenPool, networkDetails);
    }

    function configureTokenPool(
        uint256 _fork,
        RebaseToken _targetRebaseToken,
        TokenPool _sourceTokenPool,
        TokenPool _targetTokenPool,
        Register.NetworkDetails memory _targetNetworkDetails
    ) public {
        // Step 13) Configure Token Pool on Ethereum Sepolia
        vm.selectFork(_fork);

        vm.startPrank(owner);
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(address(_targetTokenPool));
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: _targetNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(address(_targetRebaseToken)),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            })
        });
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        _sourceTokenPool.applyChainUpdates(
            remoteChainSelectorsToRemove,
            chains
        );
        vm.stopPrank();
    }

    function transferTokensByBridge(
        uint256 _amountToSend,
        uint256 _sourceFork,
        uint256 _targetFork,
        RebaseToken _sourceRebaseToken,
        RebaseToken _targetRebaseToken,
        Register.NetworkDetails memory _sourceNetworkDetails,
        Register.NetworkDetails memory _targetNetworkDetails
    ) public {
        // Step 15) Transfer tokens from Ethereum Sepolia to Avalanche Fuji
        vm.selectFork(_sourceFork);

        address linkEthSepoliaAddress = _sourceNetworkDetails.linkAddress;
        address routerEthSepoliaAddress = _sourceNetworkDetails.routerAddress;
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(alice), 20 ether);

        Client.EVMTokenAmount[]
            memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        tokenToSendDetails[0] = Client.EVMTokenAmount({
            token: address(_sourceRebaseToken),
            amount: _amountToSend
        });

        vm.startPrank(alice);

        _sourceRebaseToken.approve(routerEthSepoliaAddress, _amountToSend);
        IERC20(linkEthSepoliaAddress).approve(
            routerEthSepoliaAddress,
            20 ether
        );

        uint256 balanceOfAliceBeforeEthSepolia = _sourceRebaseToken.balanceOf(
            alice
        );
        console.log(
            "balanceOfAliceBeforeEthSepolia:",
            balanceOfAliceBeforeEthSepolia
        );

        IRouterClient(routerEthSepoliaAddress).ccipSend(
            _targetNetworkDetails.chainSelector,
            Client.EVM2AnyMessage({
                receiver: abi.encode(address(alice)),
                data: "",
                tokenAmounts: tokenToSendDetails,
                extraArgs: "", // 可以不设置，或者设置为 Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000}))
                feeToken: linkEthSepoliaAddress
            })
        );

        uint256 balanceOfAliceAfterEthSepolia = _sourceRebaseToken.balanceOf(
            alice
        );
        console.log(
            "balanceOfAliceAfterEthSepolia:",
            balanceOfAliceAfterEthSepolia
        );
        vm.stopPrank();

        assertEq(
            balanceOfAliceAfterEthSepolia,
            balanceOfAliceBeforeEthSepolia - _amountToSend
        );

        vm.selectFork(_targetFork);
        uint256 balanceOfAliceBeforeTarget = _targetRebaseToken.balanceOf(
            alice
        );
        console.log("balanceOfAliceBeforeTarget:", balanceOfAliceBeforeTarget);

        vm.selectFork(_sourceFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(_targetFork);

        vm.selectFork(_targetFork);
        uint256 balanceOfAliceAfterTarget = _targetRebaseToken.balanceOf(alice);
        assertEq(
            balanceOfAliceAfterTarget,
            balanceOfAliceBeforeTarget + _amountToSend
        );
    }

    function testTransferTokensByBridge() public {
        //  step1: configure token pool on Ethereum Sepolia
        configureTokenPool(
            ethSepoliaFork,
            arbSepoliaRebaseToken,
            ethSepoliaRebaseTokenPool,
            arbSepoliaRebaseTokenPool,
            arbSepoliaNetworkDetails
        );

        configureTokenPool(
            arbSepoliaFork,
            ethSepoliaRebaseToken,
            arbSepoliaRebaseTokenPool,
            ethSepoliaRebaseTokenPool,
            ethSepoliaNetworkDetails
        );

        // step2: alice deposit tp Vault on Ethereum Sepolia
        vm.selectFork(ethSepoliaFork);
        vm.deal(address(alice), 100 ether);
        uint256 depositAmount = 50 ether;
        vm.startPrank(alice);
        vault.deposit{value: depositAmount}();
        uint256 aliceStartBalanceOnEthSepolia = IERC20(
            address(ethSepoliaRebaseToken)
        ).balanceOf(alice);
        console.log(
            "aliceStartBalanceOnEthSepolia:",
            aliceStartBalanceOnEthSepolia
        );
        assertEq(aliceStartBalanceOnEthSepolia, depositAmount);

        uint256 transferAmount = 30 ether;

        // step3: transfer tokens from Ethereum Sepolia to Avalanche Fuji
        transferTokensByBridge(
            transferAmount,
            ethSepoliaFork,
            arbSepoliaFork,
            ethSepoliaRebaseToken,
            arbSepoliaRebaseToken,
            ethSepoliaNetworkDetails,
            arbSepoliaNetworkDetails
        );

        vm.stopPrank();
    }
}
