use starknet::ContractAddress;

#[starknet::interface]
trait ICardsImpl<TContractState> {
    fn claim_card(ref self: TContractState, minter: ContractAddress, tokenId: u256, amount: u256);
    fn set_allowed_caller(ref self: TContractState, contract: ContractAddress, allowed: bool);
    fn claim_batch_card(
        ref self: TContractState,
        minter: ContractAddress,
        token_ids: Span<u256>,
        amounts: Span<u256>
    );
    fn set_base_uri(ref self: TContractState, base_uri: ByteArray);
    fn token_uri(self: @TContractState, token_id: u256) -> ByteArray;
}
