#[starknet::contract]
mod Cards {
    use openzeppelin::token::erc1155::erc1155::ERC1155Component::InternalTrait;
    use starknet::{ContractAddress, get_caller_address};
    use atemu::interfaces::cards::ICardsImpl;
    use openzeppelin::security::{PausableComponent, ReentrancyGuardComponent};
    use openzeppelin::token::erc1155::{ERC1155Component, ERC1155HooksEmptyImpl};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::access::ownable::OwnableComponent;
    use array::ArrayTrait;

    component!(path: ERC1155Component, storage: erc1155, event: erc1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: ownableEvent);
    component!(path: ReentrancyGuardComponent, storage: reentrancy, event: reentrancyEvent);
    component!(path: PausableComponent, storage: pausable, event: pausableEvent);

    #[abi(embed_v0)]
    impl ERC1155Impl = ERC1155Component::ERC1155MixinImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    impl InternalOwnableImple = OwnableComponent::InternalImpl<ContractState>;

    impl InternalPausableImpl = PausableComponent::InternalImpl<ContractState>;

    impl InternalReentrancyImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        // caller address => is allowed
        allowedCaller: LegacyMap::<ContractAddress, bool>,
        #[substorage(v0)]
        erc1155: ERC1155Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reentrancy: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        erc1155Event: ERC1155Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ownableEvent: OwnableComponent::Event,
        #[flat]
        reentrancyEvent: ReentrancyGuardComponent::Event,
        #[flat]
        pausableEvent: PausableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, tokenUri: ByteArray,) {
        self.ownable.initializer(owner);
        self.erc1155.initializer(tokenUri);
    }

    #[abi(embed_v0)]
    impl CardsImpl of ICardsImpl<ContractState> {
        fn claimCard(
            ref self: ContractState, minter: ContractAddress, tokenId: u256, amount: u256
        ) {
            self.reentrancy.start();
            let caller = get_caller_address();
            self.assertOnlyAllowedCaller(caller);

            self
                .erc1155
                .mint_with_acceptance_check(minter, tokenId, amount, ArrayTrait::new().span());

            self.reentrancy.end();
        }

        fn setAllowedCaller(ref self: ContractState, contract: ContractAddress, allowed: bool) {
            self.ownable.assert_only_owner();
            self.allowedCaller.write(contract, allowed);
        }
    }

    #[generate_trait]
    impl InternalImpl of IInternalImpl {
        fn assertOnlyAllowedCaller(self: @ContractState, caller: ContractAddress) {
            assert(self.allowedCaller.read(caller), 'Cards: Only Allowed Caller');
        }
    }
}
