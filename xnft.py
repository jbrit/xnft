import click
import json
import re
import subprocess

from eth_abi import encode
from dotenv import dotenv_values

env_config = dotenv_values(".env")

with open("relayers.json") as fp:
    relayers_list: list[dict] = list(filter(lambda r: "sepolia" in r["name"], json.load(fp)))  # testnet only for now
    relayers_mapping: dict[str, dict] = dict()
    for relayer in relayers_list:
        relayers_mapping[relayer["name"]] = relayer

chains = list(map(lambda x: str(x["name"]), relayers_list))

# some helpers
def abi_encode(types: tuple[str], args: tuple[str]):
    return "0x"+encode(types, args).hex()

def is_evm_address(address: str):
    address = address.strip()
    return re.match(r'^(0x)?[0-9a-f]{40}$', address, flags=re.IGNORECASE) is not None

def run_command(command: list[str]):
    return subprocess.check_output(command).decode()

def parse_spoke_chain_option(base_network_id: str, arg: str) -> list[dict]:
    spoke_chains = list(map(lambda chain: relayers_mapping.get(chain.strip()), filter(lambda chain: len(chain.strip()) > 0, arg.split(','))))
    if base_network_id in spoke_chains:
        raise click.BadParameter(f'spoke-network-ids also has the base chain id')
    for spoke_chain in spoke_chains:
        if spoke_chain is None:
            raise click.BadParameter(f'spoke-network-ids contains chain id {spoke_chain} which is not supported')
    return spoke_chains

def register_peer(peer_address, relayer: dict, other_relayer: dict, other_address: str):
    return run_command(["cast", "send", peer_address, "--rpc-url", relayer["rpc_url"], "setRegisteredPeer(uint16,address)", str(other_relayer["chain_id"]), other_address,"--account", "deployer"])



@click.group()
def cli():
    """This script is an helper for native cross chain nfts, powered by wormhole.

    \b
    Start cross chain deployment:
        python xnft.py create 0xA11B01A56f170b244250ae925A05490dA207C80C --network-id base_sepolia --spoke-network-ids arbitrum_sepolia

        python xnft.py --help
        python xnft.py create 0x2Ae4Bc7B461AE14cf09aB1987Fa0e1846b9C8363 --network-id base_sepolia --spoke-network-ids arbitrum_sepolia --nft-name "Cross-Chain NFT" --nft-symbol XNFT
        python xnft.py verify-nft-wrapper NFT_WRAPPER_ADDRESS --network-id base_sepolia --nft-address 0x2Ae4Bc7B461AE14cf09aB1987Fa0e1846b9C8363 
        python xnft.py verify-spoke-nft --network-id arbitrum_sepolia 0x2Ae4Bc7B461AE14cf09aB1987Fa0e1846b9C8363 --nft-name "Cross-Chain NFT" --nft-symbol XNFT
        python xnft.py register-peers --network-ids base_sepolia,arbitrum_sepolia --addresses 0xdca4DAbE79B16F98E59bD9B3f2A5ea0AB07c45a6,0x2Ae4Bc7B461AE14cf09aB1987Fa0e1846b9C8363

        cast abi-encode "c(uint16,address)" 10003 0xcD4bde67fe7C6Eb601d03a35Ea8a55eB2b136965

    """
    pass

@cli.command()
@click.argument('nft-address')
@click.option('--network-id', prompt='NFT Chain', help=f'The chain the nft was deployed. (one of: {", ".join(chains)})')
@click.option('--spoke-network-ids', prompt='Spoke Chains', help=f'The chain(s) the spoke nft should deployed. Should be comma separated (one of: {", ".join(chains)})')
@click.option('--nft-name', prompt='NFT Name', help=f'The name of the NFT collection to be used on spoke chains')
@click.option('--nft-symbol', prompt='NFT Symbol', help=f'The symbol of the NFT collection to be used on spoke chains')
def create(nft_address: str, network_id: str, nft_name: str, nft_symbol: str, spoke_network_ids: str):
    """This command creates the xnft"""
    if not is_evm_address(nft_address):
        raise click.BadParameter("Invalid nft address provided")
    if network_id not in chains:
        raise click.BadParameter(f'`network-id` should be one of: {", ".join(chains)}')
    relayer = relayers_mapping[network_id]
    spoke_relayers = parse_spoke_chain_option(base_network_id=network_id, arg=spoke_network_ids)
    
    # args - (address _tokenAddress, address _wormholeRelayer, uint16 _chainId)
    deployed_wrapper = run_command(["forge", "create", "HubNFTWrapper", "--rpc-url", relayer["rpc_url"], "--account", "deployer",
                                    "--constructor-args", nft_address, relayer["relayer"], str(relayer["chain_id"])])

    wrapper_address_match = re.search(r'Deployed to: (0x[a-fA-F0-9]{40})', deployed_wrapper)
    if not wrapper_address_match:
        raise Exception(f"Unknown Error Getting Wrapper Contract Address: Deploy Wrapper Output: \n{deployed_wrapper}")
    nft_wrapper_address = str(wrapper_address_match.group(1))
    click.secho(f'NFT Wrapper deployed to: {nft_wrapper_address}', fg='green')

    deployed_spoke_addresses = []
    for spoke_relayer in spoke_relayers:
        # args - (string memory name, string memory symbol, uint16 _chainId)
        deployed_spoke = run_command(["forge", "create", "SpokeNFT", "--rpc-url", spoke_relayer["rpc_url"], "--account", "deployer",
                                      "--constructor-args", nft_name, nft_symbol, str(spoke_relayer["chain_id"])])
        spoke_address_match = re.search(r'Deployed to: (0x[a-fA-F0-9]{40})', deployed_spoke)
        if not spoke_address_match:
            raise Exception(f"Unknown Error Getting Spoke NFT Contract Address ({spoke_relayer['name']}): Deploy Spoke Output: \n{deployed_spoke}")
        spoke_address = str(spoke_address_match.group(1))
        deployed_spoke_addresses.append(spoke_address)
        click.secho(f"Spoke NFT deployed to ({spoke_relayer['name']}): {spoke_address}", fg='green')

@cli.command()
@click.option('--network-ids', required=True, help=f'Comma separated value of networks wrapper and spoke(s). (one of: {", ".join(chains)})')
@click.option('--addresses', required=True, help=f'Comma separated value of addresses wrapper and spoke(s). (one of: {", ".join(chains)})')
def register_peers(addresses, network_ids):
    """This command registers the peer contracts for cross chain transactions"""
    spoke_relayers = parse_spoke_chain_option(base_network_id=0, arg=network_ids)
    address_list: list[str] = []
    for address in addresses.split(','):
        address = str(address).strip()
        if not is_evm_address(address):
            raise click.BadParameter(f"Bad address '{address}' provided")
        address_list.append(address)

    if len(spoke_relayers) != len(address_list):
            raise click.BadParameter(f"Same number of networks and addresses are needed")
    
    peers = list(zip(address_list, spoke_relayers))
    for address_, relayer_ in peers:
        for address, relayer in peers:
            if relayer_["name"] == relayer["name"]:
                continue
            click.echo(register_peer(address_, relayer_, relayer, address))
            click.secho(f"Registered peer {address}({relayer['name']}) on peer {address_}({relayer_['name']})", fg='green')

@cli.command()
@click.argument('nft-wrapper-address')
@click.option('--nft-address', required=True)
@click.option('--network-id', required=True, help=f'The chain the nft wrapper should verified. (one of: {", ".join(chains)})')
@click.option('--etherscan-api-key', help=f'The corresponding api key for the specified chain')
def verify_nft_wrapper(nft_wrapper_address, nft_address, network_id, etherscan_api_key):
    """This command verifies an nft wrapper on etherscan (or equivalent) for the corrseponding `network-id`"""
    if network_id not in chains:
        raise click.BadParameter(f'`network-id` should be one of: {", ".join(chains)}')
    relayer = relayers_mapping[network_id]

    if not etherscan_api_key and (etherscan_api_key := env_config.get(relayer["etherscan_env"])) is None:
        raise click.BadParameter(f'`etherscan-api-key` is required in options or .env')

    abi_encoded = abi_encode(("address","address","uint16"), (nft_address, relayer["relayer"], relayer["chain_id"]))
    verified_contract = run_command(["forge", "verify-contract", nft_wrapper_address, "HubNFTWrapper", "--chain", relayer["name"].replace("_","-"),
                                     "--etherscan-api-key",  etherscan_api_key, "--constructor-args", abi_encoded, "--watch"])
    print(verified_contract)

@cli.command()
@click.argument('spoke-nft-address')
@click.option('--nft-name', required=True)
@click.option('--nft-symbol',required=True)
@click.option('--network-id', required=True, help=f'The chain the spoke nft should verified. (one of: {", ".join(chains)})')
@click.option('--etherscan-api-key', help=f'The corresponding api key for the specified chain')
def verify_spoke_nft(spoke_nft_address, nft_name, nft_symbol, network_id, etherscan_api_key):
    """This command verifies a spoke nft contract on etherscan (or equivalent) for the corrseponding `network-id`"""
    if network_id not in chains:
        raise click.BadParameter(f'`network-id` should be one of: {", ".join(chains)}')
    relayer = relayers_mapping[network_id]
    if not etherscan_api_key and (etherscan_api_key := env_config.get(relayer["etherscan_env"])) is None:
        raise click.BadParameter(f'`etherscan-api-key` is required in options or .env')
    abi_encoded = abi_encode(("string","string","uint16"), (nft_name, nft_symbol, relayer["chain_id"]))
    verified_contract = run_command(["forge", "verify-contract", spoke_nft_address, "SpokeNFT", "--chain", relayer["name"].replace("_","-"),
                                     "--etherscan-api-key",  etherscan_api_key, "--constructor-args", abi_encoded, "--watch"])
    print(verified_contract)

@cli.command()
@click.option('--network-id', prompt='Target Chain', help=f'The chain the nft should deployed. (one of: {", ".join(chains)})')
def deploy_test_nft(network_id):
    """This command deploys a test nft to `network-id` for testing"""
    if network_id not in chains:
        raise click.BadParameter(f'`network-id` should be one of: {", ".join(chains)}')
    relayer = relayers_mapping[network_id]
    deployed_test_nft = run_command(["forge", "create", "XNFT", "--rpc-url", relayer["rpc_url"], "--account", "deployer", "--chain", relayer["name"].replace("_","-")])
    print(deployed_test_nft)

@cli.command()
@click.argument('test-nft-address')
@click.option('--network-id', required=True, help=f'The chain the spoke nft should verified. (one of: {", ".join(chains)})')
@click.option('--etherscan-api-key', help=f'The corresponding api key for the specified chain')
def verify_test_nft(test_nft_address, network_id, etherscan_api_key):
    """This command verifies a test nft contract on etherscan (or equivalent) for the corrseponding `network-id`"""
    if network_id not in chains:
        raise click.BadParameter(f'`network-id` should be one of: {", ".join(chains)}')
    relayer = relayers_mapping[network_id]
    if not etherscan_api_key and (etherscan_api_key := env_config.get(relayer["etherscan_env"])) is None:
        raise click.BadParameter(f'`etherscan-api-key` is required in options or .env')
    verified_contract = run_command(["forge", "verify-contract", test_nft_address, "XNFT", "--chain", relayer["name"].replace("_","-"), "--etherscan-api-key",  etherscan_api_key, "--watch"])
    print(verified_contract)


if __name__ == '__main__':
    cli()