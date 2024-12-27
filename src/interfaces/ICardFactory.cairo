use starknet::{ContractAddress, ClassHash};


#[derive(Drop, Serde, Copy, starknet::Store)]
struct PackTokenDetail {
    pack_address: ContractAddress,
    card_collectible: ContractAddress,
    phase_id: u256,
    token_id: u256,
    minter: ContractAddress,
}

#[derive(Drop, Serde, Copy, starknet::Store)]
struct CardDistribution {
    token_id: u256,
    name: felt252,
    class: felt252,
    rarity: felt252,
    rate: u256,
}

#[derive(Drop, Serde, Copy, starknet::Store)]
struct PackCardDetail {
    pack_address: ContractAddress,
    card_collectible: ContractAddress,
    phase_id: u256,
    num_cards: u32
}

#[starknet::interface]
trait ICardFactory<TContractState> {
    fn create_card_collectible(
        ref self: TContractState, base_uri: ByteArray, pack_address: ContractAddress, num_cards: u32
    );
    fn unpack_card_collectible(
        ref self: TContractState, collectible: ContractAddress, phase_id: u256, token_id: u256
    );
    fn set_card_collectible_class(ref self: TContractState, new_class_hash: ClassHash);
    fn set_callback_fee_limit(ref self: TContractState, callback_fee_limit: u128);
    fn set_max_callback_fee_deposit(ref self: TContractState, max_callback_fee_deposit: u256);

    fn update_pack_card_details(
        ref self: TContractState,
        collectible: ContractAddress,
        pack_address: ContractAddress,
        num_cards: u32
    );
    fn add_card_distributions(
        ref self: TContractState,
        collectible: ContractAddress,
        phase_id: u256,
        cards: Array<CardDistribution>,
    );
    fn update_card_distributions(
        ref self: TContractState,
        collectible: ContractAddress,
        phase_id: u256,
        cards: Array<CardDistribution>
    );
    fn create_new_phase(
        ref self: TContractState,
        collectible: ContractAddress,
        pack_address: ContractAddress,
        num_cards: u32
    );
    fn get_all_phase_for_card(
        self: @TContractState, collectible: ContractAddress
    ) -> Array<PackCardDetail>;
    fn get_unpack_card_details(
        self: @TContractState, collectible: ContractAddress, phase_id: u256
    ) -> PackCardDetail;
    fn get_card_collectible_class(self: @TContractState) -> ClassHash;
    fn get_callback_fee_limit(self: @TContractState) -> u128;
    fn get_max_callback_fee_deposit(self: @TContractState) -> u256;
    fn get_all_cards_addresses(self: @TContractState) -> Array<ContractAddress>;
    fn get_card_distribution_phase(
        self: @TContractState, collectible: ContractAddress, phase_id: u256
    ) -> Array<CardDistribution>;
    fn get_phase_id(
        self: @TContractState, collectible: ContractAddress, pack_address: ContractAddress
    ) -> u256;
}
