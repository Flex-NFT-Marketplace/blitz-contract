use starknet::ContractAddress;

#[starknet::interface]
pub trait IPragmaVRF<TContractState> {
    fn receive_random_words(
        ref self: TContractState,
        requestor_address: ContractAddress,
        request_id: u64,
        random_words: Span<felt252>,
        calldata: Array<felt252>
    );
}

#[starknet::contract]
mod CardFactory {
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, deploy_syscall, get_contract_address,
        get_block_timestamp, get_tx_info
    };
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePathEntry, StoragePointerWriteAccess, Vec, VecTrait,
        MutableVecTrait
    };
    use pragma_lib::abi::{IRandomnessDispatcher, IRandomnessDispatcherTrait};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin::introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
    use openzeppelin::access::ownable::{
        OwnableComponent, interface::{IOwnableDispatcher, IOwnableDispatcherTrait}
    };
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancyguard, event: ReentrancyGuardEvent
    );
    use core::TryInto;

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl InternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    use atemu::interfaces::ICardFactory::{
        ICardFactory, PackTokenDetail, CardDistribution, PackCardDetail
    };
    use atemu::interfaces::ICards::{ICardsImplDispatcher, ICardsImplDispatcherTrait};

    #[storage]
    struct Storage {
        is_card_collectible: Map<ContractAddress, bool>,
        all_card_collectibles: Vec<ContractAddress>,
        eth_dispatcher: IERC20Dispatcher,
        nonce: u64,
        randomness_contract_address: ContractAddress,
        mapping_request_pack: Map<u64, PackTokenDetail>,
        card_collectible_class: ClassHash,
        collectible_salt: u256,
        mapping_card_distribution: Map<(ContractAddress, u256), Vec<CardDistribution>>,
        mapping_card_all_phase: Map<ContractAddress, Vec<PackCardDetail>>,
        mapping_card_pack_details: Map<(ContractAddress, u256), PackCardDetail>,
        callback_fee_limit: u128,
        max_callback_fee_deposit: u256,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancyguard: ReentrancyGuardComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetUnpackCardPhase: SetUnpackCardPhase,
        UnpackPack: UnpackPack,
        CardsMinted: CardsMinted,
        SetDistributions: SetDistributions,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event
    }

    #[derive(Drop, Copy, starknet::Event)]
    struct SetUnpackCardPhase {
        #[key]
        owner: ContractAddress,
        collectible: ContractAddress,
        pack_address: ContractAddress,
        phase_id: u256,
        num_cards: u32
    }

    #[derive(Drop, Copy, starknet::Event)]
    struct UnpackPack {
        #[key]
        caller: ContractAddress,
        collectible: ContractAddress,
        pack_address: ContractAddress,
        token_id: u256
    }

    #[derive(Drop, Copy, starknet::Event)]
    struct CardsMinted {
        request_id: u64,
        minter: ContractAddress,
        card_collectible: ContractAddress,
        num_cards: u32,
        token_ids_span: Span<u256>
    }

    #[derive(Drop, Copy, starknet::Event)]
    struct SetDistributions {
        collectible: ContractAddress,
        phase_id: u256,
        total_cards: u32,
    }

    mod Errors {
        pub const CALLER_NOT_RANDOMNESS: felt252 = 'Caller not randomness contract';
        pub const INVALID_ADDRESS: felt252 = 'Invalid address';
        pub const REQUESTOR_NOT_SELF: felt252 = 'Requestor is not self';
        pub const INVALID_PACK_OWNER: felt252 = 'Caller not Pack Owner';
        pub const INVALID_COLLECTIBLE: felt252 = 'Only Card Collectible';
        pub const INVALID_PHASE_ID: felt252 = 'Only Existed Phase';
        pub const PACK_ADDRESS_NOT_FOUND: felt252 = 'Pack address not found';
        pub const INVALID_NUMBER: felt252 = 'Invalid number';
    }

    pub const PUBLISH_DELAY: u64 = 1; // return the random value asap
    pub const NUM_OF_WORDS: u64 = 1; // 1 numbers

    const TWO_TO_THE_50: u256 = 1125899906842624; // This is 2^50 in decimal

    // Sepolia : 0x60c69136b39319547a4df303b6b3a26fab8b2d78de90b6bd215ce82e9cb515c
    // Mainnet : 0x4fb09ce7113bbdf568f225bc757a29cb2b72959c21ca63a7d59bdb9026da661

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        card_collectible_class: ClassHash,
        randomness_contract_address: ContractAddress,
        eth_address: ContractAddress,
        callback_fee_limit: u128,
        max_callback_fee_deposit: u256,
    ) {
        assert(randomness_contract_address.is_non_zero(), Errors::INVALID_ADDRESS);
        assert(eth_address.is_non_zero(), Errors::INVALID_ADDRESS);
        assert(callback_fee_limit != 0, Errors::INVALID_NUMBER);
        assert(max_callback_fee_deposit != 0, Errors::INVALID_NUMBER);
        self.ownable.initializer(owner);
        self.callback_fee_limit.write(callback_fee_limit);
        self.max_callback_fee_deposit.write(max_callback_fee_deposit);
        self.card_collectible_class.write(card_collectible_class);
        self.randomness_contract_address.write(randomness_contract_address);
        self.eth_dispatcher.write(IERC20Dispatcher { contract_address: eth_address });
    }

    #[abi(embed_v0)]
    impl CardFactoryImpl of ICardFactory<ContractState> {
        fn create_card_collectible(
            ref self: ContractState,
            base_uri: ByteArray,
            pack_address: ContractAddress,
            num_cards: u32
        ) {
            self.reentrancyguard.start();
            assert(pack_address.is_non_zero(), Errors::INVALID_ADDRESS);

            let caller = get_caller_address();

            let salt = self.collectible_salt.read();
            self.collectible_salt.write(salt + 1);

            let mut constructor_calldata = ArrayTrait::<felt252>::new();
            constructor_calldata.append(caller.into());
            constructor_calldata.append(base_uri.data.len().into());
            for i in 0
                ..base_uri
                    .data
                    .len() {
                        constructor_calldata.append((*base_uri.data.at(i)).into());
                    };
            constructor_calldata.append(base_uri.pending_word);
            constructor_calldata.append(base_uri.pending_word_len.into());

            let (collectible, _) = deploy_syscall(
                self.get_card_collectible_class(),
                salt.try_into().unwrap(),
                constructor_calldata.span(),
                false
            )
                .ok()
                .unwrap();

            self.is_card_collectible.entry(collectible).write(true);
            self.all_card_collectibles.append().write(collectible);

            let phase_id = 1;
            let pack_card_detail = PackCardDetail {
                pack_address, card_collectible: collectible, phase_id, num_cards
            };

            self.mapping_card_pack_details.entry((collectible, phase_id)).write(pack_card_detail);
            self.mapping_card_all_phase.entry(collectible).append().write(pack_card_detail);
            self
                .emit(
                    SetUnpackCardPhase {
                        owner: caller, collectible, pack_address, phase_id, num_cards
                    }
                );
            self.reentrancyguard.end();
        }

        fn unpack_card_collectible(
            ref self: ContractState, collectible: ContractAddress, phase_id: u256, token_id: u256
        ) {
            self.assert_only_card_collectible(collectible);
            self.assert_only_existed_phase_id(collectible, phase_id);
            let caller = get_caller_address();

            let phase_details = self.get_unpack_card_details(collectible, phase_id);
            let pack_address = phase_details.pack_address;
            let pack_dispatcher = IERC721Dispatcher { contract_address: pack_address };
            assert(pack_dispatcher.owner_of(token_id) == caller, Errors::INVALID_PACK_OWNER);
            pack_dispatcher.transfer_from(caller, get_contract_address(), token_id);

            let request_id = self._request_randomness();

            let pack_token_detail = PackTokenDetail {
                pack_address, card_collectible: collectible, phase_id, token_id, minter: caller
            };

            self.mapping_request_pack.entry(request_id).write(pack_token_detail);
            self.emit(UnpackPack { caller, collectible, pack_address, token_id });
        }

        fn update_pack_card_details(
            ref self: ContractState,
            collectible: ContractAddress,
            pack_address: ContractAddress,
            num_cards: u32
        ) {
            self.ownable.assert_only_owner();
            self.assert_only_card_collectible(collectible);
            let phase_id = self.get_phase_id(collectible, pack_address);

            let new_card_pack_details = PackCardDetail {
                pack_address, card_collectible: collectible, phase_id, num_cards
            };
            self
                .mapping_card_pack_details
                .entry((collectible, phase_id))
                .write(new_card_pack_details);

            self
                .emit(
                    SetUnpackCardPhase {
                        owner: self.ownable.owner(), collectible, pack_address, phase_id, num_cards
                    }
                );
        }

        fn set_card_collectible_class(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.card_collectible_class.write(new_class_hash);
        }

        fn set_callback_fee_limit(ref self: ContractState, callback_fee_limit: u128) {
            self.ownable.assert_only_owner();
            self.callback_fee_limit.write(callback_fee_limit);
        }

        fn set_max_callback_fee_deposit(ref self: ContractState, max_callback_fee_deposit: u256) {
            self.ownable.assert_only_owner();
            self.max_callback_fee_deposit.write(max_callback_fee_deposit);
        }

        fn create_new_phase(
            ref self: ContractState,
            collectible: ContractAddress,
            pack_address: ContractAddress,
            num_cards: u32
        ) {
            self.ownable.assert_only_owner();
            self.assert_only_card_collectible(collectible);

            let mut phase_id = self.get_phase_id(collectible, pack_address);
            phase_id += 1;

            let pack_card_detail = PackCardDetail {
                pack_address, card_collectible: collectible, phase_id, num_cards
            };

            self.mapping_card_pack_details.entry((collectible, phase_id)).write(pack_card_detail);
            self.mapping_card_all_phase.entry(collectible).append().write(pack_card_detail);

            self
                .emit(
                    SetUnpackCardPhase {
                        owner: self.ownable.owner(), collectible, pack_address, phase_id, num_cards
                    }
                );
        }

        fn add_card_distributions(
            ref self: ContractState,
            collectible: ContractAddress,
            phase_id: u256,
            cards: Array<CardDistribution>
        ) {
            self.ownable.assert_only_owner();
            self.assert_only_card_collectible(collectible);
            self.assert_only_existed_phase_id(collectible, phase_id);

            let storage_vec = self.mapping_card_distribution.entry((collectible, phase_id));

            for i in 0
                ..cards.len() {
                    let card = cards.at(i);
                    storage_vec.append().write(card.clone());
                };

            self.emit(SetDistributions { collectible, phase_id, total_cards: cards.len() })
        }

        fn update_card_distributions(
            ref self: ContractState,
            collectible: ContractAddress,
            phase_id: u256,
            cards: Array<CardDistribution>
        ) {
            self.ownable.assert_only_owner();
            self.assert_only_card_collectible(collectible);
            self.assert_only_existed_phase_id(collectible, phase_id);

            let storage_vec = self.mapping_card_distribution.entry((collectible, phase_id));
            let length: u32 = storage_vec.len().try_into().unwrap();

            for i in 0
                ..cards
                    .len() {
                        let card = cards.at(i);
                        let index: u64 = i.try_into().unwrap();
                        if i < length {
                            storage_vec.at(index).write(card.clone());
                        } else {
                            storage_vec.append().write(card.clone());
                        }
                    };

            if cards.len() < length {
                let excess_count = length - cards.len();
                let start_index = cards.len();

                for i in start_index
                    ..start_index
                        + excess_count {
                            let index: u64 = i.try_into().unwrap();
                            storage_vec
                                .at(index)
                                .write(
                                    CardDistribution {
                                        token_id: 0,
                                        name: 0,
                                        class: 0,
                                        rarity: 0,
                                        rate: u256 { low: 0, high: 0 },
                                    }
                                );
                        }
            }

            self.emit(SetDistributions { collectible, phase_id, total_cards: cards.len() })
        }

        fn get_all_phase_for_card(
            self: @ContractState, collectible: ContractAddress
        ) -> Array<PackCardDetail> {
            let all_phases = self.mapping_card_all_phase.entry(collectible);

            if all_phases.len() == 0 {
                return ArrayTrait::<PackCardDetail>::new();
            }

            let mut phases = ArrayTrait::new();
            for i in 0..all_phases.len() {
                phases.append(all_phases.at(i).read());
            };
            phases
        }

        fn get_unpack_card_details(
            self: @ContractState, collectible: ContractAddress, phase_id: u256
        ) -> PackCardDetail {
            let phase_details = self
                .mapping_card_pack_details
                .entry((collectible, phase_id))
                .read();
            phase_details
        }

        fn get_phase_id(
            self: @ContractState, collectible: ContractAddress, pack_address: ContractAddress
        ) -> u256 {
            let pack_details = self.mapping_card_all_phase.entry(collectible);

            let mut phase_id = 0;
            for i in 0
                ..pack_details
                    .len() {
                        let detail = pack_details.at(i).read();
                        if detail.pack_address == pack_address {
                            phase_id = detail.phase_id;
                            break;
                        }
                    };

            phase_id
        }

        fn get_card_collectible_class(self: @ContractState) -> ClassHash {
            self.card_collectible_class.read()
        }

        fn get_callback_fee_limit(self: @ContractState) -> u128 {
            self.callback_fee_limit.read()
        }

        fn get_max_callback_fee_deposit(self: @ContractState) -> u256 {
            self.max_callback_fee_deposit.read()
        }

        fn get_all_cards_addresses(self: @ContractState) -> Array<ContractAddress> {
            let mut collectibles = ArrayTrait::new();
            for i in 0
                ..self
                    .all_card_collectibles
                    .len() {
                        collectibles.append(self.all_card_collectibles.at(i).read());
                    };
            collectibles
        }

        fn get_card_distribution_phase(
            self: @ContractState, collectible: ContractAddress, phase_id: u256
        ) -> Array<CardDistribution> {
            let distributions = self.mapping_card_distribution.entry((collectible, phase_id));

            if distributions.len() == 0 {
                return ArrayTrait::<CardDistribution>::new();
            }

            let mut card_distributions = ArrayTrait::new();
            for i in 0
                ..distributions.len() {
                    card_distributions.append(distributions.at(i).read());
                };
            card_distributions
        }
    }

    #[abi(embed_v0)]
    impl PragmaVRF of super::IPragmaVRF<ContractState> {
        fn receive_random_words(
            ref self: ContractState,
            requestor_address: ContractAddress,
            request_id: u64,
            random_words: Span<felt252>,
            calldata: Array<felt252>
        ) {
            let caller = get_caller_address();
            assert(
                caller == self.randomness_contract_address.read(), Errors::CALLER_NOT_RANDOMNESS
            );

            let this = get_contract_address();
            assert(requestor_address == this, Errors::REQUESTOR_NOT_SELF);
            // Unpack card
            self._mint_cards(request_id, random_words.at(0));
        }
    }

    #[generate_trait]
    impl InternalFactoryImpl of InternalImplTrait {
        fn assert_only_card_collectible(self: @ContractState, collectible: ContractAddress) {
            let is_card_collectible = self.is_card_collectible.entry(collectible).read();
            assert(is_card_collectible, Errors::INVALID_COLLECTIBLE);
        }
        fn assert_only_existed_phase_id(
            self: @ContractState, collectible: ContractAddress, phase_id: u256
        ) {
            let pack = self.mapping_card_pack_details.entry((collectible, phase_id)).read();

            let pack_phase_id = pack.phase_id;

            assert(pack_phase_id != 0, Errors::INVALID_PHASE_ID);
        }
        fn _request_randomness(ref self: ContractState) -> u64 {
            let randomness_contract_address = self.randomness_contract_address.read();
            let randomness_dispatcher = IRandomnessDispatcher {
                contract_address: randomness_contract_address
            };

            let this = get_contract_address();
            let max_callback_fee_deposit = self.max_callback_fee_deposit.read();
            // Approve the randomness contract to transfer the callback deposit/fee
            let eth_dispatcher = self.eth_dispatcher.read();
            eth_dispatcher.approve(randomness_contract_address, max_callback_fee_deposit);

            let nonce = self.nonce.read();
            let callback_fee_limit = self.callback_fee_limit.read();

            // Request the randomness to be used to construct the winning combination
            let request_id = randomness_dispatcher
                .request_random(
                    nonce, this, callback_fee_limit, PUBLISH_DELAY, NUM_OF_WORDS, array![]
                );

            self.nonce.write(nonce + 1);

            request_id
        }

        fn _mint_cards(ref self: ContractState, request_id: u64, random_words: @felt252) {
            let pack_token_detail = self.mapping_request_pack.entry(request_id).read();

            let card_collectible = pack_token_detail.card_collectible;
            let minter = pack_token_detail.minter;
            let phase_id = pack_token_detail.phase_id;

            let phase_details = self.get_unpack_card_details(card_collectible, phase_id);
            let num_cards = phase_details.num_cards;

            let card_dispatcher = ICardsImplDispatcher { contract_address: card_collectible };
            let selected_cards = self
                ._select_random_cards(card_collectible, phase_id, random_words, num_cards);

            let mut token_ids_array = array![];
            let mut amounts_array = array![];

            for i in 0
                ..selected_cards
                    .len() {
                        let token_id: u256 = selected_cards[i].token_id.clone();
                        token_ids_array.append(token_id);

                        let amount: u256 = u256 { low: 1, high: 0 };
                        amounts_array.append(amount);
                    };

            // Mint the selected cards using claim_batch_card
            let token_ids_span = token_ids_array.span();
            let amounts_span = amounts_array.span();
            self
                .emit(
                    CardsMinted { request_id, minter, card_collectible, num_cards, token_ids_span }
                );

            card_dispatcher.claim_batch_card(minter, token_ids_span, amounts_span);
        }

        fn _select_random_cards(
            self: @ContractState,
            card_collectible: ContractAddress,
            phase_id: u256,
            random_words: @felt252,
            num_cards: u32
        ) -> Array<CardDistribution> {
            let distributions = self.mapping_card_distribution.entry((card_collectible, phase_id));

            if distributions.len() == 0 {
                return ArrayTrait::<CardDistribution>::new();
            }
            let all_cards = self.get_card_distribution_phase(card_collectible, phase_id);

            // Initialize an empty array to hold the selected cards
            let mut selected_cards = array![];

            let random_words_desnap: felt252 = *random_words;
            // Convert felt252 to u256
            let mut random_value_u256: u256 = random_words_desnap.into();
            let total_weight: u256 = self._calculate_total_weight(all_cards);

            let all_cards = self.get_card_distribution_phase(card_collectible, phase_id);

            for _ in 0
                ..num_cards {
                    let chunk: u256 = random_value_u256 & (TWO_TO_THE_50 - 1); // Mask 50 bits

                    // Normalize the chunk to be in the range 0-9999
                    let random_value_normalized: u256 = chunk % total_weight;

                    // Calculate which card this random number corresponds to
                    let mut cumulative_weight = 0;

                    let len_u64: u64 = distributions.len();
                    let len_u32: u32 = len_u64.try_into().unwrap();

                    for j in 0
                        ..len_u32 {
                            let card = all_cards.at(j);
                            cumulative_weight += card.rate.clone();
                            if random_value_normalized < cumulative_weight {
                                selected_cards.append(card.clone());
                                break;
                            }
                        };

                    // Shift the random value to the right by 50 bits (not dividing, just shift
                    // bits)
                    random_value_u256 = random_value_u256 / TWO_TO_THE_50;
                };

            selected_cards
        }

        fn _calculate_total_weight(
            self: @ContractState, all_cards: Array<CardDistribution>
        ) -> u256 {
            let mut total_weight: u256 = 0;
            let mut i = 0;
            let len = all_cards.len();
            while i < len {
                let card = all_cards.at(i);
                total_weight = total_weight + *card.rate;
                i += 1;
            };
            total_weight
        }
    }
}

