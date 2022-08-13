// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";

contract FreeCityGame_v1 is
    Initializable,
    ContextUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC721EnumerableUpgradeable,
    ERC721BurnableUpgradeable,
    ERC721PausableUpgradeable,
    ERC2981Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    //nft的属性
    // life 生命剩余值 挖矿次数
    // grade 等级
    // quality r s ssr

    struct VoiceAttr {
        uint128 life;
        uint128 grade;
        uint256 parent;
        uint256 quality;
        uint256 mother;
        address creator;
        string tokenURI;
    }
    struct Claim {
        address to;
        uint256 tokenId;
        uint256 end;
    }
    uint256 public constant MAXMINTLIMIT = 8;
    uint256 public constant BLOCKCLAIN = 6171;
    //tokenId => token 属性
    mapping(uint256 => VoiceAttr) private voiceAttrs;

    mapping(uint256 => bool) private freeCityPool;

    mapping(uint256 => Claim) private claims;

    // tokenid =>hash

    mapping(uint256 => string) private _tokenURIs;

    mapping(address => bool) public isAllowlistAddress;
    //预售

    mapping(address => VoiceAttr) private preSales;

    address private openSea;
    address private whilteAddress;

    //blindbox index to tokenId
    mapping(uint256 => uint256) private blindBoxs;
    //blindbox taotal sum
    uint256 public blindBoxTotal;
    uint256 public blindBoxCurrentData;
    uint256 public blindBoxEndDay;
    string public blindBoxBaseUrl;
    //当前开盲盒的进度
    uint256 public curblindBoxIndex;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    CountersUpgradeable.Counter private _tokenIdTracker;
    event Deposit(address indexed, uint256 indexed, uint256);
    event Exchange(address indexed, address indexed, uint256);
    event Mint(address indexed, address indexed, uint256);
    event Synthesis(uint256 indexed, uint256, uint256);
    event Withdraw(address indexed, uint256);
    event Find(address indexed, address indexed, uint256);
    event Open(uint256 indexed, uint256);
    event StartBlind(uint256 indexed, uint256 indexed, string);
    event BatchMint(uint256 indexed);

    function initialize(string memory name, string memory symbol)
        public
        virtual
        initializer
    {
        __ERC721_init_unchained(name, symbol);
        __Pausable_init_unchained();
        __FreeCityGame_init_unchained(name, symbol);
        _tokenIdTracker.increment();
    }

    function __FreeCityGame_init_unchained(string memory, string memory)
        internal
        onlyInitializing
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    string private _baseTokenURI;

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    function burn(uint256 tokenId) public override {
        _burn(tokenId);
    }

    function tokensOfOwner(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);
        uint256[] memory tokensId = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokensId;
    }

    function allowlistAddresses(address[] calldata wAddresses)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < wAddresses.length; i++) {
            isAllowlistAddress[wAddresses[i]] = true;
        }
    }

    function ____Voice721_init_init_unchained(
        string memory,
        string memory,
        string memory baseTokenURI
    ) internal onlyInitializing {
        _baseTokenURI = baseTokenURI;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    function allOwner(uint256 parent, uint256 mother)
        internal
        view
        returns (bool)
    {
        return
            _isApprovedOrOwner(_msgSender(), parent) &&
            _isApprovedOrOwner(_msgSender(), mother);
    }

    function grantMintRole(address to) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "n1");
        _grantRole(MINTER_ROLE, to);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function exist(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }

    function setWhiteListAddress(address first)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(blindBoxEndDay != 0, "n1");
        // require(AddressUpgradeable.isContract(first), "n2");
        whilteAddress = first;
    }

    function startNewBlindBox(
        uint256 total,
        uint256 date,
        string memory _baseUri
    ) public onlyRole(MINTER_ROLE) {
        blindBoxTotal = total;
        blindBoxCurrentData = 0;
        blindBoxEndDay = block.timestamp + date * 86400; //86400表示一天
        blindBoxBaseUrl = _baseUri;
        emit StartBlind(blindBoxTotal, blindBoxEndDay, blindBoxBaseUrl);
    }

    function openBlindBox(string memory _tokenUrl)
        external
        onlyRole(MINTER_ROLE)
    {
        uint256 end;
        if (blindBoxTotal <= 100) {
            end = blindBoxTotal;
        } else if (curblindBoxIndex + 100 > blindBoxTotal) {
            end = blindBoxTotal;
        } else {
            end = curblindBoxIndex + 100;
        }
        for (uint256 i = curblindBoxIndex; i < end; i++) {
            voiceAttrs[blindBoxs[i]].tokenURI = string(
                abi.encodePacked(_tokenUrl, "/", blindBoxs[i], ".json")
            );
        }
        curblindBoxIndex = curblindBoxIndex + 100;
        emit Open(curblindBoxIndex, blindBoxTotal);
    }

    function openAllBox(string memory _tokenUrl)
        external
        onlyRole(MINTER_ROLE)
    {
        for (uint256 i = curblindBoxIndex; i < blindBoxTotal; i++) {
            voiceAttrs[blindBoxs[i]].tokenURI = string(
                abi.encodePacked(_tokenUrl, "/", blindBoxs[i], ".json")
            );
        }
        emit Open(curblindBoxIndex, blindBoxTotal);
    }

    function updateBlindBox(uint256 _blindBoxTotal)
        external
        onlyRole(MINTER_ROLE)
    {
        blindBoxTotal = _blindBoxTotal;
    }

    function batchMint(address[] memory tos, uint256[] memory qualities)
        public
    {
        require(msg.sender == whilteAddress, "n1");
        require(
            blindBoxTotal > 0 && blindBoxCurrentData <= blindBoxTotal,
            "n2"
        );
        require(block.timestamp <= blindBoxEndDay, "n3");
        require(tos.length == qualities.length, "n4");
        for (uint256 i = 0; i < tos.length; i++) {
            uint256 count = _tokenIdTracker.current();
            _safeMint(tos[i], count);
            blindBoxCurrentData = blindBoxCurrentData + 1;
            blindBoxs[blindBoxCurrentData] = count;
            voiceAttrs[count] = VoiceAttr(
                0,
                0,
                0,
                qualities[i],
                0,
                _msgSender(),
                blindBoxBaseUrl
            );
            _tokenIdTracker.increment();
        }
        emit BatchMint(tos.length);
    }

    function preMint(address to, uint256 quality) public {
        require(msg.sender == whilteAddress, "n1");
        require(
            blindBoxTotal > 0 && blindBoxCurrentData <= blindBoxTotal,
            "n2"
        );
        require(block.timestamp <= blindBoxEndDay, "n3");
        _safeMint(to, _tokenIdTracker.current());
        blindBoxCurrentData = blindBoxCurrentData + 1;
        blindBoxs[blindBoxCurrentData] = _tokenIdTracker.current();
        voiceAttrs[_tokenIdTracker.current()] = VoiceAttr(
            0,
            0,
            0,
            quality,
            0,
            _msgSender(),
            blindBoxBaseUrl
        );
        _tokenIdTracker.increment();
    }

    function setBlindBoxBaseUrl(string memory _blindBoxBaseUri) external {
        blindBoxBaseUrl = _blindBoxBaseUri;
    }

    function getBlindBoxBaseUrl() external view returns (string memory) {
        return blindBoxBaseUrl;
    }

    function blindBox(address to) public view {
        require(isAllowlistAddress[to], "not is whiltelist user");
    }

    //1010101010101010101
    /**
     *  tokenData 按照NFT属性生成tokenid和图片
     * 第一位 1-5 ,表示 品质
     * 后面每两位表示一个部位，总长度19位
     *
     */
    function mint(
        address to,
        uint256 quality,
        string calldata _tokenURI
    ) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "n2");
        // can be burned (destroyed), so we need a separate counter.
        _safeMint(to, _tokenIdTracker.current());
        voiceAttrs[_tokenIdTracker.current()] = VoiceAttr(
            0,
            0,
            0,
            quality,
            0,
            _msgSender(),
            _tokenURI
        );
        _tokenIdTracker.increment();
    }

    function synthesis(
        uint256 parent,
        uint256 mother,
        uint256 quality,
        address to,
        string calldata _tokenURI
    ) public {
        require(freeCityPool[parent] && freeCityPool[mother], "n1");
        require(hasRole(MINTER_ROLE, _msgSender()), "n2");
        require(voiceAttrs[parent].life < MAXMINTLIMIT, "n3");
        require(voiceAttrs[mother].life < MAXMINTLIMIT, "n3");
        unchecked {
            voiceAttrs[mother].life = voiceAttrs[mother].life + 1;
            voiceAttrs[mother].life = voiceAttrs[mother].life + 1;
        }
        uint256 id = _tokenIdTracker.current();
        _mint(to, id);
        voiceAttrs[id] = VoiceAttr(
            0,
            0,
            parent,
            quality,
            mother,
            _msgSender(),
            _tokenURI
        );
        _tokenIdTracker.increment();
        emit Synthesis(id, parent, mother);
    }

    function deposit(uint256 tokenId, uint256 userId) external nonReentrant {
        require(_exists(tokenId), "n1");
        require(freeCityPool[tokenId] == false, "n2");
        require(_isApprovedOrOwner(_msgSender(), tokenId), "n3");
        freeCityPool[tokenId] = true;
        emit Deposit(_msgSender(), userId, tokenId);
    }

    function exchange(
        uint256 tokenId,
        address to,
        uint128 life,
        uint128 grade
    ) external {
        require(hasRole(MINTER_ROLE, msg.sender), "n1");
        require(freeCityPool[tokenId] == true, "n2");
        address owner = ERC721Upgradeable.ownerOf(tokenId);
        voiceAttrs[tokenId].life = life;
        voiceAttrs[tokenId].grade = grade;
        _transfer(owner, to, tokenId);
        emit Exchange(owner, to, tokenId);
    }

    function isStaking(uint256 tokenId) public view returns (bool) {
        return freeCityPool[tokenId];
    }

    /**
     *  do not stake status
     */
    function transfer(address to, uint256 _tokenId) external {
        require(freeCityPool[_tokenId] == false, "n1");
        safeTransferFrom(msg.sender, to, _tokenId);
    }

    function withdraw(
        address to,
        uint256 tokenId,
        uint128 life,
        uint128 grade
    ) external onlyRole(MINTER_ROLE) {
        require(_exists(tokenId), "nonexistent token");
        require(freeCityPool[tokenId] == true, "n1");
        require(claims[tokenId].end == 0, "n3");
        voiceAttrs[tokenId].life = life;
        voiceAttrs[tokenId].grade = grade;
        address owner = ERC721Upgradeable.ownerOf(tokenId);
        if (owner != to) {
            _transfer(owner, to, tokenId);
        }
        freeCityPool[tokenId] = false;
        delete freeCityPool[tokenId];
        emit Withdraw(to, tokenId);
    }

    function setOpenSea(address _openSea)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        openSea = _openSea;
    }

    function getOpenSea() public view returns (address) {
        return openSea;
    }

    /**
     * Override isApprovedForAll to auto-approve OS's proxy contract
     */
    function isApprovedForAll(address _owner, address _operator)
        public
        view
        override(ERC721Upgradeable, IERC721Upgradeable)
        returns (bool isOperator)
    {
        // if OpenSea's ERC721 Proxy Address is detected, auto-return true
        // for Polygon's Mumbai testnet, use 0xff7Ca10aF37178BdD056628eF42fD7F799fAc77c
        if (openSea != address(0) && _operator == openSea) {
            return true;
        }
        // otherwise, use the default ERC721.isApprovedForAll()
        return ERC721Upgradeable.isApprovedForAll(_owner, _operator);
    }

    function claim(uint256 tokenId) external {
        require(_exists(tokenId), "n1");
        require(claims[tokenId].end < block.number, "n2");
        require(claims[tokenId].to == _msgSender(), "n3");
        delete freeCityPool[tokenId];
        emit Withdraw(claims[tokenId].to, tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "nonexistent token");
        return voiceAttrs[tokenId].tokenURI;
    }


    function updateTokenUri(uint256 tokenId,string memory _tokenUrl) external onlyRole(MINTER_ROLE){
         require(_exists(tokenId), "n1");
         voiceAttrs[tokenId].tokenURI=_tokenUrl;
    }
    function updateMutData(
        uint256 tokenId,
        uint128 life,
        uint128 grade
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_exists(tokenId), "n1");
        voiceAttrs[tokenId].life = life;
        voiceAttrs[grade].life = grade;
    }

    function metaMutData(uint256 _tokenId)
        public
        view
        returns (
            uint128 life,
            uint128 grade,
            bool status,
            string memory uri
        )
    {
        require(_exists(_tokenId), "n1");
        return (
            voiceAttrs[_tokenId].life,
            voiceAttrs[_tokenId].grade,
            freeCityPool[_tokenId],
            tokenURI(_tokenId)
        );
    }

    /**
     * @notice Sets the royalty information that all ids in this contract will default to.
     *
     * Requirements:
     *
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @notice Sets the royalty information for a specific token id, overriding the global default.
     *
     * Requirements:
     *
     * - `tokenId` must be already minted.
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(
            ERC721Upgradeable,
            AccessControlEnumerableUpgradeable,
            ERC721EnumerableUpgradeable,
            ERC2981Upgradeable
        )
        returns (bool)
    {
        return
            interfaceId ==
            type(AccessControlEnumerableUpgradeable).interfaceId ||
            interfaceId == type(IERC721EnumerableUpgradeable).interfaceId ||
            interfaceId == type(ERC2981Upgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    )
        internal
        override(
            ERC721EnumerableUpgradeable,
            ERC721PausableUpgradeable,
            ERC721Upgradeable
        )
    {
        super._beforeTokenTransfer(from, to, tokenId);
        require(!paused(), "pause tx");
    }

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {}

    uint256[48] private __gap;
}