#[starknet::contract]
mod Fuel {
    use openzeppelin::security::interface::IPausable;
    use atemu::interfaces::{
        fuel::IFuel, point::{IPointPoolDispatcher, IPointPoolDispatcherTrait},
        cards::{ICardsImplDispatcher, ICardsImplDispatcherTrait}
    };
    use starknet::{
        ContractAddress, SyscallResult, SyscallResultTrait, get_block_timestamp, get_caller_address,
        get_contract_address, get_tx_info
    };
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::{PausableComponent, ReentrancyGuardComponent};
    use openzeppelin::account::interface::{AccountABIDispatcher, AccountABIDispatcherTrait};
    use alexandria_storage::{List, ListTrait};
    use hash::{HashStateTrait, HashStateExTrait};
    use pedersen::PedersenTrait;

    const STARKNET_DOMAIN_TYPE_HASH: felt252 =
        selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");

    const WINNER_STRUCT_TYPE_HASH: felt252 =
        selector!(
            "WinnerStruct(poolId:u256,winner:ContractAddress,cardId:u256,amountCards:u256)u256(low:felt,high:felt)"
        );

    const U256_TYPE_HASH: felt252 = selector!("u256(low:felt,high:felt)");

    component!(path: OwnableComponent, storage: ownable, event: ownableEvent);
    component!(path: ReentrancyGuardComponent, storage: reentrancy, event: reentrancyEvent);
    component!(path: PausableComponent, storage: pausable, event: pausableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    impl InternalOwnableImple = OwnableComponent::InternalImpl<ContractState>;

    impl InternalPausableImpl = PausableComponent::InternalImpl<ContractState>;

    impl InternalReentrancyImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        // Atemu Point contract address
        pointAddress: ContractAddress,
        // card contract address
        cardAddress: ContractAddress,
        // Duration between start time and end time
        duration: u64,
        currentPoolId: u256,
        // Pool id => Pool Detail
        idToPool: LegacyMap::<u256, PoolDetail>,
        // proof => is used
        usedProof: LegacyMap::<felt252, bool>,
        // (player address, pool id) => staked amount
        playerStakedAmount: LegacyMap::<(ContractAddress, u256), u256>,
        // Pool id => List of participants
        participants: LegacyMap::<u256, List<ContractAddress>>,
        // Address of Who draw the winner
        drawer: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancy: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        duration: u64,
        pointAddress: ContractAddress,
        cardAddress: ContractAddress,
        drawer: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.duration.write(duration);
        self.pointAddress.write(pointAddress);
        self.cardAddress.write(cardAddress);
        self.currentPoolId.write(0);
        self.drawer.write(drawer);
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CreatePool: CreatePool,
        JoiningPool: JoiningPool,
        CancelPool: CancelPool,
        ClaimReward: ClaimReward,
        #[flat]
        ownableEvent: OwnableComponent::Event,
        #[flat]
        reentrancyEvent: ReentrancyGuardComponent::Event,
        #[flat]
        pausableEvent: PausableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct CreatePool {
        #[key]
        id: u256,
        startAt: u64,
        endAt: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct CancelPool {
        #[key]
        id: u256,
        canceledAt: u64
    }

    #[derive(Drop, starknet::Event)]
    struct JoiningPool {
        #[key]
        player: ContractAddress,
        poolId: u256,
        stakedAmount: u256,
        joinedAt: u64
    }

    #[derive(Drop, starknet::Event)]
    struct ClaimReward {
        #[key]
        poolId: u256,
        winner: ContractAddress,
        totalPoints: u256,
        cardAddress: ContractAddress,
        cardId: u256,
        amountCards: u256,
        timestamp: u64
    }

    #[derive(Drop, Copy, Serde, starknet::Store)]
    struct PoolDetail {
        id: u256,
        startAt: u64,
        endAt: u64,
        totalStaked: u256,
        status: u8, // 0 for not open, 1 for opening
        winner: ContractAddress,
    }

    #[derive(Drop, Copy, Serde, Hash)]
    struct StarknetDomain {
        name: felt252,
        version: felt252,
        chain_id: felt252,
    }

    #[derive(Drop, Copy, Serde, Hash)]
    struct WinnerStruct {
        poolId: u256,
        winner: ContractAddress,
        cardId: u256,
        amountCards: u256
    }

    #[abi(embed_v0)]
    impl FuelImple of IFuel<ContractState> {
        fn manuallyCreatePool(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.assertNotPause();
            self._createNewPool();
        }

        fn joiningPool(ref self: ContractState, poolId: u256, amountPoint: u256) {
            self.reentrancy.start();
            self.assertNotPause();

            let mut poolDetail = self.getPoolDetail(poolId);
            self.assertValidOpenedPool(poolId);

            let player = get_caller_address();
            let pointDispatcher = IPointPoolDispatcher {
                contract_address: self.getPoolPointAddress()
            };
            pointDispatcher.transferFrom(player, get_contract_address(), amountPoint);

            let currentStaked = self.getStakedPoint(player, poolId);
            self.playerStakedAmount.write((player, poolId), currentStaked + amountPoint);

            if (currentStaked == 0) {
                let mut participants = self.participants.read(poolId);
                participants.append(player);
                self.participants.write(poolId, participants);
            }

            poolDetail.totalStaked += amountPoint;
            self.idToPool.write(poolId, poolDetail);

            self
                .emit(
                    JoiningPool {
                        player, poolId, stakedAmount: amountPoint, joinedAt: get_block_timestamp()
                    }
                );

            self.reentrancy.end();
        }

        fn cancelPool(ref self: ContractState, poolId: u256) {
            self.ownable.assert_only_owner();

            let mut poolDetail = self.getPoolDetail(poolId);
            poolDetail.status = 0;

            self.idToPool.write(poolId, poolDetail);
            let pointDispatcher = IPointPoolDispatcher {
                contract_address: self.getPoolPointAddress()
            };

            let participants = self.getArrayParticipants(poolId);
            let mut index: u32 = 0;
            loop {
                if (index == participants.len()) {
                    break;
                }

                let player = *participants.at(index);
                pointDispatcher.transfer(player, self.playerStakedAmount.read((player, poolId)));
                index += 1;
            };

            self.emit(CancelPool { id: poolId, canceledAt: get_block_timestamp() });
        }

        fn updateDuration(ref self: ContractState, duration: u64) {
            self.ownable.assert_only_owner();
            self.duration.write(duration);
        }

        fn updatePoolPointAddress(ref self: ContractState, pointAddress: ContractAddress) {
            self.ownable.assert_only_owner();
            self.pointAddress.write(pointAddress);
        }

        fn updateCardAddress(ref self: ContractState, cardAddress: ContractAddress) {
            self.ownable.assert_only_owner();
            self.cardAddress.write(cardAddress);
        }

        fn updateDrawer(ref self: ContractState, drawer: ContractAddress) {
            self.ownable.assert_only_owner();
            self.drawer.write(drawer);
        }

        fn claimReward(
            ref self: ContractState,
            poolId: u256,
            cardId: u256,
            amountCards: u256,
            proof: Array::<felt252>
        ) {
            self.reentrancy.start();
            self.assertNotPause();
            self.assertClosedPool(poolId);

            let caller = get_caller_address();
            assert(self.getStakedPoint(caller, poolId) > 0, 'FUEL: Caller Not Participated');

            let messageHash = self
                ._getMessageHash(caller, poolId, cardId, amountCards, self.getDrawer());
            assert(
                self.isValidSignature(self.getDrawer(), messageHash, proof) == 'VALID',
                'FUEL: Invalid Proof'
            );

            assert(!self.usedProof.read(messageHash), 'FUEL: Proof Already Used');
            self.usedProof.write(messageHash, true);

            let mut poolDetail = self.getPoolDetail(poolId);
            poolDetail.winner = caller;
            self.idToPool.write(poolId, poolDetail);

            let pointDispatcher = IPointPoolDispatcher {
                contract_address: self.getPoolPointAddress()
            };
            pointDispatcher.transfer(caller, poolDetail.totalStaked);

            let cardDispatcher = ICardsImplDispatcher { contract_address: self.getCardAddress() };
            cardDispatcher.claimCard(caller, cardId, amountCards);

            self
                .emit(
                    ClaimReward {
                        poolId,
                        winner: caller,
                        totalPoints: poolDetail.totalStaked,
                        cardAddress: self.getCardAddress(),
                        cardId,
                        amountCards,
                        timestamp: get_block_timestamp()
                    }
                );
            self.reentrancy.end();
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    impl ViewFunction of ViewFunctionTrait {
        #[external(v0)]
        fn getCurrentPoolId(self: @ContractState) -> u256 {
            self.currentPoolId.read()
        }

        #[external(v0)]
        fn getPoolDetail(self: @ContractState, poolId: u256) -> PoolDetail {
            self.idToPool.read(poolId)
        }

        #[external(v0)]
        fn getDuration(self: @ContractState) -> u64 {
            self.duration.read()
        }

        #[external(v0)]
        fn getArrayParticipants(self: @ContractState, poolId: u256) -> Array<ContractAddress> {
            self.participants.read(poolId).array().unwrap_syscall()
        }

        #[external(v0)]
        fn getPoolPointAddress(self: @ContractState) -> ContractAddress {
            self.pointAddress.read()
        }

        #[external(v0)]
        fn getCardAddress(self: @ContractState) -> ContractAddress {
            self.cardAddress.read()
        }

        #[external(v0)]
        fn getStakedPoint(self: @ContractState, player: ContractAddress, poolId: u256) -> u256 {
            self.playerStakedAmount.read((player, poolId))
        }

        #[external(v0)]
        fn getDrawer(self: @ContractState) -> ContractAddress {
            self.drawer.read()
        }

        #[external(v0)]
        fn pause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.assertNotPause();
            self.pausable._pause();
        }

        #[external(v0)]
        fn unpause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.assertPaused();
            self.pausable._unpause();
        }
    }

    trait IStructHash<T> {
        fn hashStruct(self: @T) -> felt252;
    }

    impl StructHashStarknetDomain of IStructHash<StarknetDomain> {
        fn hashStruct(self: @StarknetDomain) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(STARKNET_DOMAIN_TYPE_HASH);
            state = state.update_with(*self);
            state = state.update_with(4);
            state.finalize()
        }
    }

    impl StructHashU256 of IStructHash<u256> {
        fn hashStruct(self: @u256) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(U256_TYPE_HASH);
            state = state.update_with(*self);
            state = state.update_with(3);
            state.finalize()
        }
    }

    impl StructHashWinner of IStructHash<WinnerStruct> {
        fn hashStruct(self: @WinnerStruct) -> felt252 {
            let mut state = PedersenTrait::new(0);
            state = state.update_with(WINNER_STRUCT_TYPE_HASH);
            state = state.update_with(self.poolId.hashStruct());
            state = state.update_with(*self.winner);
            state = state.update_with(self.cardId.hashStruct());
            state = state.update_with(self.amountCards.hashStruct());
            state = state.update_with(5);
            state.finalize()
        }
    }


    #[generate_trait]
    impl InternalImpl of InternalImplTrait {
        fn _createNewPool(ref self: ContractState) {
            let mut poolId = self.getCurrentPoolId();
            let startTime = get_block_timestamp();

            if poolId >= 1 {
                let previousPool = self.getPoolDetail(poolId);

                if (previousPool.status != 0) {
                    assert(startTime >= previousPool.endAt, 'FUEL: Previous Pool Not End Yet');
                    let currentParticipents = self.getArrayParticipants(poolId);
                    if currentParticipents.len() >= 3 {
                        poolId += 1;
                    }
                }
            } else {
                poolId += 1;
            }
            let mut poolDetail = self.getPoolDetail(poolId);

            poolDetail.id = poolId;
            poolDetail.startAt = startTime;
            poolDetail.endAt = startTime + self.getDuration();
            poolDetail.status = 1;
            self.idToPool.write(poolId, poolDetail);
            self.currentPoolId.write(poolId);
            self
                .emit(
                    CreatePool { id: poolId, startAt: poolDetail.startAt, endAt: poolDetail.endAt }
                );
        }

        fn assertValidOpenedPool(self: @ContractState, poolId: u256) {
            let poolDetail = self.getPoolDetail(poolId);
            assert(poolDetail.status == 1, 'FUEL: Invalid Opened Pool');

            let blockTime = get_block_timestamp();
            assert(
                poolDetail.startAt <= blockTime && blockTime < poolDetail.endAt,
                'FUEL: Pool Not Open'
            );
        }

        fn assertClosedPool(self: @ContractState, poolId: u256) {
            let poolDetail = self.getPoolDetail(poolId);
            let blockTime = get_block_timestamp();
            assert(poolDetail.endAt <= blockTime, 'FUEL: Pool Not End Yet');
        }

        fn _getMessageHash(
            self: @ContractState,
            winner: ContractAddress,
            poolId: u256,
            cardId: u256,
            amountCards: u256,
            signer: ContractAddress
        ) -> felt252 {
            let domain = StarknetDomain {
                name: 'Fuel', version: 1, chain_id: get_tx_info().unbox().chain_id
            };
            let mut state = PedersenTrait::new(0);
            state = state.update_with('StarkNet Message');
            state = state.update_with(domain.hashStruct());
            state = state.update_with(signer);
            let winner = WinnerStruct { poolId, winner, cardId, amountCards };
            state = state.update_with(winner.hashStruct());
            state = state.update_with(4);
            state.finalize()
        }

        fn isValidSignature(
            self: @ContractState, signer: ContractAddress, hash: felt252, signature: Array<felt252>
        ) -> felt252 {
            let account: AccountABIDispatcher = AccountABIDispatcher { contract_address: signer };
            account.is_valid_signature(hash, signature)
        }

        fn assertNotPause(self: @ContractState) {
            assert(!self.is_paused(), 'FUEL: Game Is Paused');
        }

        fn assertPaused(self: @ContractState) {
            assert(self.is_paused(), 'FUEL: Game Is Not Pause');
        }
    }
}
