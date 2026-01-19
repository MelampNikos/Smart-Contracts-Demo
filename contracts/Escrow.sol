pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Escrow is EIP712 {
    enum ServiceState { OPEN, CLOSED }
    enum EscrowState { PENDING_ACCEPTANCE, AWAITING_DELIVERY, COMPLETE, REFUNDED, CANCELLED }

    struct Service {
        address seller;
        string title;
        string description;
        uint256 price;
        ServiceState state;
        uint256 createdAt;
    }

    struct EscrowDetails {
        uint256 serviceId;
        address buyer;
        address seller;
        uint256 amount;
        EscrowState state;
        string buyerMessage;
        uint256 createdAt;
    }

    uint256 public serviceCount;
    uint256 public escrowCount;
    mapping(uint256 => Service) public services;
    mapping(uint256 => EscrowDetails) public escrows;

    address public owner;
    uint256 public platformFeeTokens = 250;

    // EIP-712 type hashes
    bytes32 private constant OFFER_TYPEHASH =
        keccak256("Offer(uint256 serviceId,uint256 amount,address buyer,address seller,uint256 nonce,uint256 deadline,string buyerMessage)");
    
    bytes32 private constant ACCEPT_OFFER_TYPEHASH =
        keccak256("AcceptOffer(uint256 escrowId,address seller,uint256 nonce,uint256 deadline)");
    
    bytes32 private constant APPROVE_DELIVERY_TYPEHASH =
        keccak256("ApproveDelivery(uint256 escrowId,address buyer,uint256 nonce,uint256 deadline)");
    
    bytes32 private constant CANCEL_OFFER_TYPEHASH =
        keccak256("CancelOffer(uint256 escrowId,address buyer,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) public nonces;

    // Events for services
    event ServiceCreated(uint256 indexed serviceId, address indexed seller, string title, uint256 price);
    event ServiceClosed(uint256 indexed serviceId);

    // Events for escrows
    event OfferMade(uint256 indexed escrowId, uint256 indexed serviceId, address indexed buyer, uint256 amount);
    event OfferAccepted(uint256 indexed escrowId);
    event OfferRejected(uint256 indexed escrowId);
    event DeliveryApproved(uint256 indexed escrowId);
    event FundsReleased(uint256 indexed escrowId, uint256 sellerAmount, uint256 platformFee);
    event Refunded(uint256 indexed escrowId, uint256 amount);

    constructor() EIP712("Escrow", "1") {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function createService(string calldata _title, string calldata _description, uint256 _price) external returns (uint256) {
        require(_price > 0);

        uint256 serviceId = serviceCount++;
        
        services[serviceId] = Service({
            seller: msg.sender,
            title: _title,
            description: _description,
            price: _price,
            state: ServiceState.OPEN,
            createdAt: block.timestamp
        });

        emit ServiceCreated(serviceId, msg.sender, _title, _price);
        return serviceId;
    }

    function closeService(uint256 _serviceId) external {
        Service storage service = services[_serviceId];
        require(msg.sender == service.seller);
        require(service.state == ServiceState.OPEN);
        
        service.state = ServiceState.CLOSED;
        emit ServiceClosed(_serviceId);
    }

    function makeOffer(uint256 _serviceId, string calldata _message) external payable returns (uint256) {
        Service storage service = services[_serviceId];
        require(service.state == ServiceState.OPEN);
        require(msg.sender != service.seller);
        require(msg.value > 0);

        uint256 escrowId = escrowCount++;
        
        escrows[escrowId] = EscrowDetails({
            serviceId: _serviceId,
            buyer: msg.sender,
            seller: service.seller,
            amount: msg.value,
            state: EscrowState.PENDING_ACCEPTANCE,
            buyerMessage: _message,
            createdAt: block.timestamp
        });

        emit OfferMade(escrowId, _serviceId, msg.sender, msg.value);
        return escrowId;
    }

    function acceptOffer(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.seller);
        require(escrow.state == EscrowState.PENDING_ACCEPTANCE);

        escrow.state = EscrowState.AWAITING_DELIVERY;
        emit OfferAccepted(_escrowId);
    }

    function rejectOffer(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.seller);
        require(escrow.state == EscrowState.PENDING_ACCEPTANCE);

        escrow.state = EscrowState.REFUNDED;
        uint256 refundAmount = escrow.amount;
        escrow.amount = 0;

        payable(escrow.buyer).transfer(refundAmount);

        emit OfferRejected(_escrowId);
        emit Refunded(_escrowId, refundAmount);
    }

    function cancelOffer(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.buyer);
        require(escrow.state == EscrowState.PENDING_ACCEPTANCE);

        escrow.state = EscrowState.CANCELLED;
        uint256 refundAmount = escrow.amount;
        escrow.amount = 0;

        payable(escrow.buyer).transfer(refundAmount);

        emit Refunded(_escrowId, refundAmount);
    }

    function approveDelivery(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.buyer);
        require(escrow.state == EscrowState.AWAITING_DELIVERY);

        escrow.state = EscrowState.COMPLETE;

        uint256 platformFee = (escrow.amount * platformFeeTokens) / 10000;
        uint256 sellerAmount = escrow.amount - platformFee;
        escrow.amount = 0;

        payable(escrow.seller).transfer(sellerAmount);
        if (platformFee > 0) {
            payable(owner).transfer(platformFee);
        }

        emit DeliveryApproved(_escrowId);
        emit FundsReleased(_escrowId, sellerAmount, platformFee);
    }

    function requestRefund(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.buyer);
        require(escrow.state == EscrowState.AWAITING_DELIVERY);

        escrow.state = EscrowState.REFUNDED;
        uint256 refundAmount = escrow.amount;
        escrow.amount = 0;

        payable(escrow.buyer).transfer(refundAmount);

        emit Refunded(_escrowId, refundAmount);
    }

    function setPlatformFee(uint256 _feeTokens) external onlyOwner {
        require(_feeTokens <= 1000);
        platformFeeTokens = _feeTokens;
    }

    function getService(uint256 _serviceId) external view returns (Service memory) {
        return services[_serviceId];
    }

    function getEscrow(uint256 _escrowId) external view returns (EscrowDetails memory) {
        return escrows[_escrowId];
    }

    function getSellerServices(address _seller) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < serviceCount; i++) {
            if (services[i].seller == _seller) count++;
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < serviceCount; i++) {
            if (services[i].seller == _seller) {
                result[index++] = i;
            }
        }
        return result;
    }

    function getOpenServices() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < serviceCount; i++) {
            if (services[i].state == ServiceState.OPEN) count++;
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < serviceCount; i++) {
            if (services[i].state == ServiceState.OPEN) {
                result[index++] = i;
            }
        }
        return result;
    }

    function getBuyerEscrows(address _buyer) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < escrowCount; i++) {
            if (escrows[i].buyer == _buyer) count++;
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < escrowCount; i++) {
            if (escrows[i].buyer == _buyer) {
                result[index++] = i;
            }
        }
        return result;
    }

    function getSellerEscrows(address _seller) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < escrowCount; i++) {
            if (escrows[i].seller == _seller) count++;
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < escrowCount; i++) {
            if (escrows[i].seller == _seller) {
                result[index++] = i;
            }
        }
        return result;
    }

    function getServiceEscrows(uint256 _serviceId) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < escrowCount; i++) {
            if (escrows[i].serviceId == _serviceId) count++;
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < escrowCount; i++) {
            if (escrows[i].serviceId == _serviceId) {
                result[index++] = i;
            }
        }
        return result;
    }

    function verifyOfferSignature(
        uint256 serviceId,
        uint256 amount,
        address buyer,
        address seller,
        uint256 nonce,
        uint256 deadline,
        string calldata buyerMessage,
        bytes calldata signature
    ) public view returns (address) {
        require(block.timestamp <= deadline);
        
        bytes32 structHash = keccak256(abi.encode(
            OFFER_TYPEHASH,
            serviceId,
            amount,
            buyer,
            seller,
            nonce,
            deadline,
            keccak256(bytes(buyerMessage))
        ));
        
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature);
    }

    function verifyAcceptOfferSignature(
        uint256 escrowId,
        address seller,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) public view returns (address) {
        require(block.timestamp <= deadline);
        
        bytes32 structHash = keccak256(abi.encode(
            ACCEPT_OFFER_TYPEHASH,
            escrowId,
            seller,
            nonce,
            deadline
        ));
        
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature);
    }

    function verifyApproveDeliverySignature(
        uint256 escrowId,
        address buyer,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) public view returns (address) {
        require(block.timestamp <= deadline);
        
        bytes32 structHash = keccak256(abi.encode(
            APPROVE_DELIVERY_TYPEHASH,
            escrowId,
            buyer,
            nonce,
            deadline
        ));
        
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature);
    }

    function verifyCancelOfferSignature(
        uint256 escrowId,
        address buyer,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) public view returns (address) {
        require(block.timestamp <= deadline);
        
        bytes32 structHash = keccak256(abi.encode(
            CANCEL_OFFER_TYPEHASH,
            escrowId,
            buyer,
            nonce,
            deadline
        ));
        
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature);
    }

    function makeOfferWithSignature(
        uint256 _serviceId,
        string calldata _message,
        uint256 deadline,
        bytes calldata signature
    ) external payable returns (uint256) {
        Service storage service = services[_serviceId];
        require(service.state == ServiceState.OPEN);
        require(msg.value > 0);

        address buyer = verifyOfferSignature(
            _serviceId,
            msg.value,
            msg.sender,
            service.seller,
            nonces[msg.sender],
            deadline,
            _message,
            signature
        );
        
        require(buyer == msg.sender);
        require(msg.sender != service.seller);
        
        nonces[msg.sender]++;

        uint256 escrowId = escrowCount++;
        
        escrows[escrowId] = EscrowDetails({
            serviceId: _serviceId,
            buyer: msg.sender,
            seller: service.seller,
            amount: msg.value,
            state: EscrowState.PENDING_ACCEPTANCE,
            buyerMessage: _message,
            createdAt: block.timestamp
        });

        emit OfferMade(escrowId, _serviceId, msg.sender, msg.value);
        return escrowId;
    }

    function acceptOfferWithSignature(
        uint256 _escrowId,
        uint256 deadline,
        bytes calldata signature
    ) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(escrow.state == EscrowState.PENDING_ACCEPTANCE);

        address seller = verifyAcceptOfferSignature(
            _escrowId,
            escrow.seller,
            nonces[escrow.seller],
            deadline,
            signature
        );
        
        require(seller == escrow.seller);
        
        nonces[escrow.seller]++;

        escrow.state = EscrowState.AWAITING_DELIVERY;
        emit OfferAccepted(_escrowId);
    }

    function approveDeliveryWithSignature(
        uint256 _escrowId,
        uint256 deadline,
        bytes calldata signature
    ) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(escrow.state == EscrowState.AWAITING_DELIVERY);

        address buyer = verifyApproveDeliverySignature(
            _escrowId,
            escrow.buyer,
            nonces[escrow.buyer],
            deadline,
            signature
        );
        
        require(buyer == escrow.buyer);
        
        nonces[escrow.buyer]++;


        escrow.state = EscrowState.COMPLETE;

        uint256 platformFee = (escrow.amount * platformFeeTokens) / 10000;
        uint256 sellerAmount = escrow.amount - platformFee;
        escrow.amount = 0;

        payable(escrow.seller).transfer(sellerAmount);
        if (platformFee > 0) {
            payable(owner).transfer(platformFee);
        }

        emit DeliveryApproved(_escrowId);
        emit FundsReleased(_escrowId, sellerAmount, platformFee);
    }

    function cancelOfferWithSignature(
        uint256 _escrowId,
        uint256 deadline,
        bytes calldata signature
    ) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(escrow.state == EscrowState.PENDING_ACCEPTANCE);

        address buyer = verifyCancelOfferSignature(
            _escrowId,
            escrow.buyer,
            nonces[escrow.buyer],
            deadline,
            signature
        );
        
        require(buyer == escrow.buyer);
        
        nonces[escrow.buyer]++;

        escrow.state = EscrowState.CANCELLED;
        uint256 refundAmount = escrow.amount;
        escrow.amount = 0;

        payable(escrow.buyer).transfer(refundAmount);

        emit Refunded(_escrowId, refundAmount);
    }
}