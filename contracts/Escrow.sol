pragma solidity ^0.8.0;

/**
 * @title Escrow
 * @dev A multi-user escrow contract for a service rental marketplace (like Fiverr).
 * Sellers create service proposals, buyers make offers, sellers accept, then delivery flow.
 */

contract Escrow {
    enum ServiceState { OPEN, CLOSED }
    enum EscrowState { PENDING_ACCEPTANCE, AWAITING_DELIVERY, COMPLETE, REFUNDED, CANCELLED }

    struct Service {
        address seller;
        string title;
        string description;
        uint256 price;  // Suggested price (buyer can offer different amount)
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

    // Platform fee (e.g., 2.5% = 250 tokens out of 10000)
    address public owner;
    uint256 public platformFeeTokens = 250; // 2.5%

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

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }


    function createService(string calldata _title, string calldata _description, uint256 _price) external returns (uint256) {
        require(bytes(_title).length > 0, "Title required");
        require(_price > 0, "Price must be greater than 0");

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

    // Seller can close their service (no new offers)
    function closeService(uint256 _serviceId) external {
        Service storage service = services[_serviceId];
        require(msg.sender == service.seller, "Only seller can close");
        require(service.state == ServiceState.OPEN, "Service not open");
        
        service.state = ServiceState.CLOSED;
        emit ServiceClosed(_serviceId);
    }

    // ==================== ESCROW FUNCTIONS ====================

    // Buyer makes an offer on a service (funds are held in escrow)
    function makeOffer(uint256 _serviceId, string calldata _message) external payable returns (uint256) {
        Service storage service = services[_serviceId];
        require(service.seller != address(0), "Service does not exist");
        require(service.state == ServiceState.OPEN, "Service not available");
        require(msg.sender != service.seller, "Seller cannot buy own service");
        require(msg.value > 0, "Must send payment");

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

    // Seller accepts the offer - work begins
    function acceptOffer(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.seller, "Only seller can accept");
        require(escrow.state == EscrowState.PENDING_ACCEPTANCE, "Invalid state");

        escrow.state = EscrowState.AWAITING_DELIVERY;
        emit OfferAccepted(_escrowId);
    }

    // Seller rejects the offer - funds returned to buyer
    function rejectOffer(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.seller, "Only seller can reject");
        require(escrow.state == EscrowState.PENDING_ACCEPTANCE, "Invalid state");

        escrow.state = EscrowState.REFUNDED;
        uint256 refundAmount = escrow.amount;
        escrow.amount = 0;

        payable(escrow.buyer).transfer(refundAmount);

        emit OfferRejected(_escrowId);
        emit Refunded(_escrowId, refundAmount);
    }

    // Buyer can cancel their offer before seller accepts
    function cancelOffer(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.buyer, "Only buyer can cancel");
        require(escrow.state == EscrowState.PENDING_ACCEPTANCE, "Cannot cancel after acceptance");

        escrow.state = EscrowState.CANCELLED;
        uint256 refundAmount = escrow.amount;
        escrow.amount = 0;

        payable(escrow.buyer).transfer(refundAmount);

        emit Refunded(_escrowId, refundAmount);
    }

    // Buyer approves the delivery and releases funds to seller
    function approveDelivery(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.buyer, "Only the buyer can approve");
        require(escrow.state == EscrowState.AWAITING_DELIVERY, "Invalid state");

        escrow.state = EscrowState.COMPLETE;

        // Calculate platform fee
        uint256 platformFee = (escrow.amount * platformFeeTokens) / 10000;
        uint256 sellerAmount = escrow.amount - platformFee;
        escrow.amount = 0;

        // Transfer funds
        payable(escrow.seller).transfer(sellerAmount);
        if (platformFee > 0) {
            payable(owner).transfer(platformFee);
        }

        emit DeliveryApproved(_escrowId);
        emit FundsReleased(_escrowId, sellerAmount, platformFee);
    }

    // Buyer requests refund if something goes wrong (after acceptance)
    function requestRefund(uint256 _escrowId) external {
        EscrowDetails storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.buyer, "Only the buyer can request refund");
        require(escrow.state == EscrowState.AWAITING_DELIVERY, "Invalid state");

        escrow.state = EscrowState.REFUNDED;
        uint256 refundAmount = escrow.amount;
        escrow.amount = 0;

        payable(escrow.buyer).transfer(refundAmount);

        emit Refunded(_escrowId, refundAmount);
    }

    // ==================== ADMIN FUNCTIONS ====================

    // Owner can update platform fee
    function setPlatformFee(uint256 _feeTokens) external onlyOwner {
        require(_feeTokens <= 1000, "Fee cannot exceed 10%");
        platformFeeTokens = _feeTokens;
    }

    // ==================== VIEW FUNCTIONS ====================

    function getService(uint256 _serviceId) external view returns (Service memory) {
        return services[_serviceId];
    }

    function getEscrow(uint256 _escrowId) external view returns (EscrowDetails memory) {
        return escrows[_escrowId];
    }

    // Get all services by a seller
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

    // Get all open services
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

    // Get all escrows for a buyer
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

    // Get all escrows for a seller
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

    // Get escrows for a specific service
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
}