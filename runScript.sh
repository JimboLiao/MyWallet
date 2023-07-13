# To load the variables in the .env file
source .env

# run script 
# forge script MyWalletScript02 --rpc-url $MOMBAI_RPC_URL --broadcast -vvvv --force --legacy

# dry run
forge script MyWalletScript02 --rpc-url $MOMBAI_RPC_URL -vvvv --force --legacy

