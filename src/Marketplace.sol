//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/utils/Counters.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

contract Marketplace is ERC721 {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    Counters.Counter public tokenId;
    Counters.Counter public soldTokenId;
    string public baseUri;
    uint256 listPrice = 0.01 ether;
    uint256 sellingPrice = 0.01 ether;
    address public owner;
    uint256 targetBalance = 10 ether;
    uint256 maxPriceChange = 10;
    uint256 timeLimit;

    event TokenMinted(uint256 tokenId);
    event MarketCreated(uint256 tokenId, uint256 price);
    event ItemPurchased(uint256 tokenId, address buyer);
    event PurchasedItemSold(uint256 tokenId, address seller);
    event OnERC721ReceivedTriggered(address, address, uint256, bytes);

    struct Item {
        uint256 _tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        bool sold;
    }

    mapping(uint256 => Item) public IdToItem;
    mapping(uint256 => bool) public readyToSell;
    mapping(uint256 => address) public tokenBuyer;

    constructor(string memory _baseUri) ERC721("GOOD_TOKEN", "GT") {
        baseUri = _baseUri;
        owner = msg.sender;
        timeLimit = block.timestamp + 120 days;
    }

    /**
     * @dev token creator function
     */
    function mint() public payable returns (uint256) {
        require(msg.value == listPrice, "Pay 0.01 ether to create a token");
        tokenId.increment();
        uint256 currentTokenId = tokenId.current();
        _safeMint(msg.sender, currentTokenId);
        tokenURI(currentTokenId);
        emit TokenMinted(currentTokenId);
        return currentTokenId;
    }

    /**
     * @dev set the token in marketplace contract for sell
     * @param _tokenId tokenId of token which is going to be submitted in contract
     * @param _price  price of the token set by caller
     */
    function createMarketItem(uint256 _tokenId, uint256 _price) public payable {
        require(msg.value == listPrice, "Pay 0.01 ether to set for sale");
        require(
            IdToItem[_tokenId].owner == msg.sender,
            "You are not the owner of this token"
        );
        require(_tokenId > 0, "Invalid tokenId");
        _safeTransfer(msg.sender, address(this), _tokenId, "");
        IdToItem[_tokenId] = Item(
            _tokenId,
            payable(msg.sender),
            payable(address(this)),
            _price,
            false
        );
        readyToSell[_tokenId] = true;
        emit MarketCreated(_tokenId, _price);
    }

    /**
     * @notice function for buying token by anyone
     * @param _tokenId  tokenId of token
     */
    function buyItem(uint256 _tokenId) public payable {
        require(readyToSell[_tokenId], "tokenId is not ready to sell yet");
        require(msg.value == IdToItem[_tokenId].price);
        _safeTransfer(address(this), msg.sender, _tokenId, "");
        (bool sent, ) = owner.call{value: listPrice}("");
        require(sent);
        (bool success, ) = IdToItem[_tokenId].seller.call{value: msg.value}("");
        require(success);

        IdToItem[_tokenId].sold = true;
        readyToSell[_tokenId] = false; // tracking unsold tokens
        soldTokenId.increment();
        tokenBuyer[_tokenId] = msg.sender;
        tokenId.decrement();
        emit ItemPurchased(_tokenId, msg.sender);
    }

    /**
     * @dev function for getting unsold items of marketplace
     */
    function getUnsoldItems() public view returns (Item[] memory) {
        uint256 totalTokenNumber = tokenId.current();

        uint256 arrayIndex = 0;
        Item[] memory items;
        for (uint256 i = 1; i <= totalTokenNumber; i++) {
            if (readyToSell[i] == true) {
                require(IdToItem[i].owner == address(this));
                require(!IdToItem[i].sold);
                Item storage currentId = IdToItem[i];
                items[arrayIndex] = currentId;
                arrayIndex++;
            }
        }

        return items;
    }

    /**
     * @dev function for getting items of particular creator
     */
    function getYourItems() public view returns (Item[] memory) {
        uint256 totalTokenNumber = tokenId.current();

        uint256 arrayIndex = 0;
        Item[] memory yourItems;
        for (uint i = 1; i < totalTokenNumber; i++) {
            if (IdToItem[i].owner == msg.sender) {
                Item storage items = IdToItem[i];
                yourItems[arrayIndex] = items;
                arrayIndex++;
            }
        }
        return yourItems;
    }

    /**
     * @dev returns all items purchased by buyer
     */
    function returnPurchasedItems() public view returns (Item[] memory) {
        uint256 totalTokenNumber = tokenId.current();
        uint256 arrayIndex = 0;
        Item[] memory purchasedItems;
        for (uint256 i = 0; i < totalTokenNumber; i++) {
            if (tokenBuyer[i] == msg.sender) {
                Item storage _purchasedItems = IdToItem[i];
                purchasedItems[arrayIndex] = _purchasedItems;
                arrayIndex++;
            }
        }
        return purchasedItems;
    }

    function sellPurchasedItems(uint256 _tokenId) public payable {
        require(
            msg.value == sellingPrice,
            "Please pay 0.01 ether to proceed selling."
        );
        require(tokenBuyer[_tokenId] == msg.sender);
        transferFrom(msg.sender, address(this), _tokenId);

        (bool success, ) = msg.sender.call{
            value: generatePriceForToken(_tokenId)
        }("");
        require(success);
        tokenId.increment();
        emit PurchasedItemSold(_tokenId, msg.sender);
    }

    /**
     * @dev algorithm for generating price based on contract's balance, here seller's loss or profit will be depended on the balance of contract. If balance of contract is
     * less than target balance then seller will get less price than item's previous price and if the balance of contract is greater than target balance then seller will get
     * more price than item's previous price.
     * @param _tokenId tokenId
     */
    function generatePriceForToken(uint256 _tokenId) public returns (uint256) {
        uint256 deviation = address(this).balance - targetBalance;
        uint256 price;
        if (deviation > 0) {
            uint256 maxPriceIncrease = (
                IdToItem[_tokenId].price.mul(maxPriceChange)
            ).div(100);

            uint256 priceIncrease = (deviation.mul(IdToItem[_tokenId].price))
                .div(targetBalance);

            if (priceIncrease > maxPriceIncrease) {
                priceIncrease = maxPriceIncrease;
            }
            price = IdToItem[_tokenId].price += priceIncrease;
        } else if (deviation < 0) {
            uint256 maxPriceDecrease = (
                IdToItem[_tokenId].price.mul(maxPriceChange)
            ).div(100);
            uint256 priceDecrease = (deviation.mul(IdToItem[_tokenId].price))
                .div(targetBalance);
            if (priceDecrease < maxPriceDecrease) {
                priceDecrease = maxPriceDecrease;
            }
            price = IdToItem[_tokenId].price -= priceDecrease;
        }

        return price;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseUri;
    }

    /**
     * @dev owner can withdraw eth every 4 months to keep the balance of contract stable so that sellers can make profit.
     */
    function withdraw() public onlyOwner {
        require(block.timestamp == timeLimit);
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success);
        timeLimit = block.timestamp + 120 days;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
     * @dev in case contract might need external funding to keep eth amount stable
     */
    receive() external payable {}
}
