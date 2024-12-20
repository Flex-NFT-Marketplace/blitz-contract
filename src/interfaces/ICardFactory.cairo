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

#[starknet::interface]
trait ICardFactory<TContractState> {
    fn create_card_collectible(
        ref self: TContractState, base_uri: ByteArray, pack_address: ContractAddress
    );
    fn unpack_card_collectible(
        ref self: TContractState, collectible: ContractAddress, phase_id: u256, token_id: u256
    );
    fn set_card_collectible_class(ref self: TContractState, new_class_hash: ClassHash);
    fn set_card_pack(
        ref self: TContractState, collectible: ContractAddress, pack_address: ContractAddress
    );
    fn add_card_distributions(
        ref self: TContractState,
        collectible: ContractAddress,
        phase_id: u256,
        cards: Array<CardDistribution>
    );
    fn update_card_distributions(
        ref self: TContractState,
        collectible: ContractAddress,
        phase_id: u256,
        cards: Array<CardDistribution>
    );
    fn get_card_pack(self: @TContractState, collectible: ContractAddress) -> ContractAddress;
    fn get_card_collectible_class(self: @TContractState) -> ClassHash;
    fn get_all_cards_addresses(self: @TContractState) -> Array<ContractAddress>;
    fn get_card_distribution_phase(
        self: @TContractState, collectible: ContractAddress, phase_id: u256
    ) -> Array<CardDistribution>;
}
