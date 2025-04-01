// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

// contrac addr: 0x5FbDB2315678afecb367f032d93F642f64180aa3
// owner addr: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

struct Campaign {
    uint256 id;
    address creator;
    uint256 threshold;
    uint256 balance;
    address beneficiary;
    uint256 numberOfVotes;
    bool closed;
}

contract Kickstarter {
    error NotExists(uint256 campaignId);
    error NotOwner();
    error NotCreator();
    error AlreadyVoted(uint256 campaignId);
    error NotEnoughEth(uint256 amount);
    error FailedTransaction();
    error ClosedCampaign(uint256 campaignId);
    error GoalNotReached(uint256 balance, uint256 threshold);

    uint256 public nextId = 1;
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    mapping(uint256 => Campaign) public idToCampaign;
    mapping(address voter => mapping(uint256 campId => uint256 amount))
        public votes;

    uint256[] public failedCampaigns;

    event CampaignCreated(
        uint256 campaignId,
        address creator,
        uint256 threshold,
        address beneficiary
    );
    event Voted(
        uint256 indexed campaignId,
        address indexed voter,
        uint256 amount
    );
    event Unvoted(
        uint256 indexed campaignId,
        address indexed voter,
        uint256 amount
    );
    event CampaignClosed(uint256 indexed campaignId, uint256 amountTransferred);
    event FundsClaimed(address owner, uint256 campaignId);

    // modifier onlyCreator(uint256 _campaignId) {
    //     if (idToCampaign[_campaignId].creator != msg.sender) {
    //         revert NotCreator();
    //     }
    //     _;
    // }

    modifier onlyOwner() {
        if (owner != msg.sender) {
            revert NotOwner();
        }
        _;
    }

    function createCampaign(
        uint256 minEthThreshold,
        address _beneficiary
    ) public {
        Campaign memory newCampaign = Campaign({
            id: nextId,
            creator: msg.sender,
            balance: 0,
            threshold: minEthThreshold, // in wei
            beneficiary: _beneficiary,
            numberOfVotes: 0,
            closed: false
        });

        idToCampaign[nextId] = newCampaign;

        emit CampaignCreated(nextId, msg.sender, minEthThreshold, _beneficiary);

        nextId++;
    }

    function vote(uint256 _campaignId) public payable {
        // Check if campaign exists
        if (idToCampaign[_campaignId].id == 0) {
            revert NotExists(_campaignId);
        }

        // Check if campaign is closed
        if (idToCampaign[_campaignId].closed) {
            revert ClosedCampaign(_campaignId);
        }

        // Only allow one vote per campaign
        //if (votes[_voter][_campaignId] != 0) {
        //  revert AlreadyVoted(_campaignId);
        //}

        // Check if the voter sent enough ETH
        if (msg.value == 0) {
            revert NotEnoughEth(msg.value);
        }

        votes[msg.sender][_campaignId] += msg.value;
        idToCampaign[_campaignId].balance += msg.value;
        idToCampaign[_campaignId].numberOfVotes++;

        emit Voted(_campaignId, msg.sender, msg.value);
    }

    function unvote(uint256 _campaignId) public {
        // Check if campaign exists
        if (idToCampaign[_campaignId].id == 0) {
            revert NotExists(_campaignId);
        }

        // Check if campaign is closed
        if (idToCampaign[_campaignId].closed) {
            revert ClosedCampaign(_campaignId);
        }

        uint256 amountToUnvote = votes[msg.sender][_campaignId];

        // Check if the voter has voted
        if (amountToUnvote == 0) {
            revert NotEnoughEth(0);
        }

        votes[msg.sender][_campaignId] = 0;
        idToCampaign[_campaignId].balance -= amountToUnvote;
        idToCampaign[_campaignId].numberOfVotes--;

        (bool success, ) = payable(msg.sender).call{value: amountToUnvote}("");
        if (!success) {
            revert FailedTransaction();
        }
        emit Unvoted(_campaignId, msg.sender, amountToUnvote);
    }

    function closeCampaign(uint256 _campaignId) public {
        // Check if campaign exists
        if (idToCampaign[_campaignId].id == 0) {
            revert NotExists(_campaignId);
        }

        // Check if the caller is the creator
        if (msg.sender != idToCampaign[_campaignId].creator) {
            revert NotCreator();
        }

        // Check if campaign is closed
        if (idToCampaign[_campaignId].closed) {
            revert ClosedCampaign(_campaignId);
        }

        // Change state
        idToCampaign[_campaignId].closed = true;
        idToCampaign[_campaignId].numberOfVotes = 0;

        Campaign storage campaign = idToCampaign[_campaignId];
        uint256 amountToTransfer = 0;

        // Check if the goal is reached
        if (campaign.balance < campaign.threshold) {
            failedCampaigns.push(_campaignId);
        } else {
            amountToTransfer = campaign.balance;
            campaign.balance = 0;

            (bool success, ) = payable(address(campaign.beneficiary)).call{
                value: amountToTransfer
            }("");
            if (!success) {
                revert FailedTransaction();
            }
        }

        emit CampaignClosed(_campaignId, amountToTransfer);
    }

    function claimFunds() public onlyOwner {
        uint256 amountClaimed = 0;

        // Only failed campaigns
        for (uint256 i = 0; i < failedCampaigns.length; i++) {
            Campaign storage campaign = idToCampaign[failedCampaigns[i]];

            amountClaimed += campaign.balance;
            emit FundsClaimed(msg.sender, campaign.id);

            campaign.balance = 0;
        }

        // Reset array
        delete failedCampaigns;
        failedCampaigns = new uint256[](0);

        if (amountClaimed > 0) {
            (bool success, ) = payable(msg.sender).call{value: amountClaimed}(
                ""
            );
            if (!success) {
                revert FailedTransaction();
            }
        }
    }

    function getCampaign(
        uint256 _campaignId
    ) public view returns (Campaign memory) {
        if (idToCampaign[_campaignId].id == 0) {
            revert NotExists(_campaignId);
        }

        return idToCampaign[_campaignId];
    }

    function getFailedCampaigns() public view returns (uint256[] memory) {
        return failedCampaigns;
    }
}
