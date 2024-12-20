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

    use atemu::interfaces::ICardFactory::{ICardFactory, PackTokenDetail, CardDistribution};
    use atemu::interfaces::ICards::{ICardsImplDispatcher, ICardsImplDispatcherTrait};

    #[storage]
    struct Storage {
        is_card_collectible: Map<ContractAddress, bool>,
        mapping_card_pack: Map<ContractAddress, ContractAddress>,
        all_card_collectibles: Vec<ContractAddress>,
        eth_dispatcher: IERC20Dispatcher,
        nonce: u64,
        randomness_contract_address: ContractAddress,
        mapping_request_pack: Map<u64, PackTokenDetail>,
        card_collectible_class: ClassHash,
        collectible_salt: u256,
        mapping_card_distribution: Map<(ContractAddress, u256), Vec<CardDistribution>>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancyguard: ReentrancyGuardComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CreateCard: CreateCard,
        UnpackPack: UnpackPack,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event
    }

    #[derive(Drop, Copy, starknet::Event)]
    struct CreateCard {
        #[key]
        owner: ContractAddress,
        collectible: ContractAddress,
        pack_address: ContractAddress
    }

    #[derive(Drop, Copy, starknet::Event)]
    struct UnpackPack {
        #[key]
        caller: ContractAddress,
        collectible: ContractAddress,
        pack_address: ContractAddress,
        token_id: u256
    }

    mod Errors {
        pub const CALLER_NOT_RANDOMNESS: felt252 = 'Caller not randomness contract';
        pub const INVALID_ADDRESS: felt252 = 'Invalid address';
        pub const REQUESTOR_NOT_SELF: felt252 = 'Requestor is not self';
        pub const INVALID_PACK_OWNER: felt252 = 'Caller not Pack Owner';
        pub const INVALID_Collectible: felt252 = 'Only Card Collectible';
    }

    pub const PUBLISH_DELAY: u64 = 1; // return the random value asap
    pub const NUM_OF_WORDS: u64 = 1; // 5 numbers
    pub const CALLBACK_FEE_LIMIT: u128 = 100_000_000_000_000_0; // 0.005 ETH
    pub const MAX_CALLBACK_FEE_DEPOSIT: u256 = 500_000_000_000_000_0; // CALLBACK_FEE_LIMIT * 5; 

    const TWO_TO_THE_50: u256 = 1125899906842624; // This is 2^50 in decimal

    // Sepolia : 0x60c69136b39319547a4df303b6b3a26fab8b2d78de90b6bd215ce82e9cb515c
    // Mainnet : 0x4fb09ce7113bbdf568f225bc757a29cb2b72959c21ca63a7d59bdb9026da661

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        card_collectible_class: ClassHash,
        randomness_contract_address: ContractAddress,
        eth_address: ContractAddress
    ) {
        assert(randomness_contract_address.is_non_zero(), Errors::INVALID_ADDRESS);
        assert(eth_address.is_non_zero(), Errors::INVALID_ADDRESS);
        self.ownable.initializer(owner);
        self.card_collectible_class.write(card_collectible_class);
        self.randomness_contract_address.write(randomness_contract_address);
        self.eth_dispatcher.write(IERC20Dispatcher { contract_address: eth_address });
    }

    #[abi(embed_v0)]
    impl CardFactoryImpl of ICardFactory<ContractState> {
        fn create_card_collectible(
            ref self: ContractState, base_uri: ByteArray, pack_address: ContractAddress,
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
            self.mapping_card_pack.entry(collectible).write(pack_address);

            self.emit(CreateCard { owner: caller, collectible, pack_address });
            self.reentrancyguard.end();
        }

        fn unpack_card_collectible(
            ref self: ContractState, collectible: ContractAddress, phase_id: u256, token_id: u256
        ) {
            self.assert_only_card_collectible(collectible);
            let caller = get_caller_address();

            let pack_address = self.get_card_pack(collectible);
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

        fn set_card_pack(
            ref self: ContractState, collectible: ContractAddress, pack_address: ContractAddress
        ) {
            self.ownable.assert_only_owner();
            self.assert_only_card_collectible(collectible);
            self.mapping_card_pack.entry(collectible).write(pack_address);
        }

        fn set_card_collectible_class(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.card_collectible_class.write(new_class_hash);
        }

        fn add_card_distributions(
            ref self: ContractState,
            collectible: ContractAddress,
            phase_id: u256,
            cards: Array<CardDistribution>
        ) {
            self.ownable.assert_only_owner();
            self.assert_only_card_collectible(collectible);

            let storage_vec = self.mapping_card_distribution.entry((collectible, phase_id));

            for i in 0
                ..cards.len() {
                    let card = cards.at(i);
                    storage_vec.append().write(card.clone());
                }
        }

        fn update_card_distributions(
            ref self: ContractState,
            collectible: ContractAddress,
            phase_id: u256,
            cards: Array<CardDistribution>
        ) {
            self.ownable.assert_only_owner();
            self.assert_only_card_collectible(collectible);

            let storage_vec = self.mapping_card_distribution.entry((collectible, phase_id));

            let existing_length = storage_vec.len();
            for i in 0
                ..existing_length {
                    storage_vec
                        .at(i)
                        .write(
                            CardDistribution {
                                token_id: 0,
                                name: 0,
                                class: 0,
                                rarity: 0,
                                rate: u256 { low: 0, high: 0 }
                            }
                        );
                };

            for i in 0
                ..cards.len() {
                    let card = cards.at(i);
                    storage_vec.append().write(card.clone());
                }
        }

        fn get_card_pack(self: @ContractState, collectible: ContractAddress) -> ContractAddress {
            self.mapping_card_pack.entry(collectible).read()
        }

        fn get_card_collectible_class(self: @ContractState) -> ClassHash {
            self.card_collectible_class.read()
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
            assert(is_card_collectible, Errors::INVALID_Collectible);
        }
        fn _request_randomness(ref self: ContractState) -> u64 {
            let randomness_contract_address = self.randomness_contract_address.read();
            let randomness_dispatcher = IRandomnessDispatcher {
                contract_address: randomness_contract_address
            };

            let this = get_contract_address();

            // Approve the randomness contract to transfer the callback deposit/fee
            let eth_dispatcher = self.eth_dispatcher.read();
            eth_dispatcher.approve(randomness_contract_address, MAX_CALLBACK_FEE_DEPOSIT);

            let nonce = self.nonce.read();

            // Request the randomness to be used to construct the winning combination
            let request_id = randomness_dispatcher
                .request_random(
                    nonce, this, CALLBACK_FEE_LIMIT, PUBLISH_DELAY, NUM_OF_WORDS, array![]
                );

            self.nonce.write(nonce + 1);

            request_id
        }

        fn _mint_cards(ref self: ContractState, request_id: u64, random_words: @felt252) {
            let pack_token_detail = self.mapping_request_pack.entry(request_id).read();

            let card_collectible = pack_token_detail.card_collectible;
            let minter = pack_token_detail.minter;
            let phase_id = pack_token_detail.phase_id;

            let card_dispatcher = ICardsImplDispatcher { contract_address: card_collectible };
            let selected_cards = self
                ._select_random_cards(card_collectible, phase_id, random_words, 5);

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

