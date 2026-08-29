-- CreateEnum
CREATE TYPE "CharacterClass" AS ENUM ('VANGUARD', 'ARCANIST', 'RANGER', 'WARDEN');

-- CreateEnum
CREATE TYPE "Gender" AS ENUM ('MALE', 'FEMALE', 'NEUTRAL');

-- CreateEnum
CREATE TYPE "Locale" AS ENUM ('PT_BR', 'ES_419', 'EN_US');

-- CreateEnum
CREATE TYPE "Faction" AS ENUM ('UNALIGNED', 'IRONVOW', 'ASHENFOLD');

-- CreateEnum
CREATE TYPE "Region" AS ENUM ('SA', 'NA');

-- CreateEnum
CREATE TYPE "CurrencyType" AS ENUM ('GOLD', 'GEMS', 'HONOR');

-- CreateEnum
CREATE TYPE "LedgerOperation" AS ENUM ('DUNGEON_REWARD', 'QUEST_REWARD', 'EVENT_REWARD', 'MAIL_ATTACHMENT', 'STORE_PURCHASE', 'IAP_CREDIT', 'MARKET_SALE', 'MARKET_PURCHASE', 'MARKET_FEE', 'ITEM_UPGRADE', 'REPAIR_COST', 'GM_ADJUSTMENT', 'REFUND');

-- CreateEnum
CREATE TYPE "ItemCategory" AS ENUM ('WEAPON', 'HELMET', 'CHEST', 'GLOVES', 'BOOTS', 'RING', 'AMULET', 'CONSUMABLE', 'MATERIAL', 'QUEST_ITEM', 'VANITY', 'CURRENCY_BUNDLE');

-- CreateEnum
CREATE TYPE "ItemRarity" AS ENUM ('COMMON', 'UNCOMMON', 'RARE', 'EPIC', 'LEGENDARY');

-- CreateEnum
CREATE TYPE "EquipSlot" AS ENUM ('MAIN_HAND', 'OFF_HAND', 'HELMET', 'CHEST', 'GLOVES', 'BOOTS', 'RING_1', 'RING_2', 'AMULET');

-- CreateEnum
CREATE TYPE "StatType" AS ENUM ('STRENGTH', 'AGILITY', 'INTELLIGENCE', 'VITALITY', 'PHYSICAL_DAMAGE', 'MAGIC_DAMAGE', 'ARMOR', 'MAGIC_RESIST', 'CRIT_CHANCE', 'CRIT_DAMAGE', 'ATTACK_SPEED', 'MOVE_SPEED', 'MAX_HP', 'MAX_RESOURCE', 'LIFE_STEAL', 'COOLDOWN_REDUCTION');

-- CreateEnum
CREATE TYPE "Difficulty" AS ENUM ('NORMAL', 'HEROIC', 'NIGHTMARE', 'INFERNO');

-- CreateEnum
CREATE TYPE "QuestType" AS ENUM ('MAIN_STORY', 'SIDE', 'DAILY', 'WEEKLY', 'ACHIEVEMENT');

-- CreateEnum
CREATE TYPE "QuestState" AS ENUM ('AVAILABLE', 'ACTIVE', 'COMPLETED', 'CLAIMED');

-- CreateEnum
CREATE TYPE "GuildRank" AS ENUM ('MEMBER', 'OFFICER', 'LEADER');

-- CreateEnum
CREATE TYPE "FriendshipState" AS ENUM ('PENDING', 'ACCEPTED', 'BLOCKED');

-- CreateEnum
CREATE TYPE "MarketState" AS ENUM ('ACTIVE', 'SOLD', 'CANCELLED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "PaymentProvider" AS ENUM ('GOOGLE_PLAY', 'APPLE_APPSTORE', 'ASAAS_PIX', 'MERCADO_PAGO', 'DLOCAL', 'STRIPE');

-- CreateEnum
CREATE TYPE "PaymentStatus" AS ENUM ('PENDING', 'PAID', 'CREDITED', 'FAILED', 'REFUNDED', 'CHARGEBACK');

-- CreateEnum
CREATE TYPE "SanctionType" AS ENUM ('WARNING', 'CHAT_MUTE', 'TEMP_BAN', 'PERMA_BAN');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "email" TEXT,
    "passwordHash" TEXT,
    "isGuest" BOOLEAN NOT NULL DEFAULT true,
    "preferredLoc" "Locale" NOT NULL DEFAULT 'PT_BR',
    "countryCode" VARCHAR(2) NOT NULL DEFAULT 'BR',
    "region" "Region" NOT NULL DEFAULT 'SA',
    "emailVerified" BOOLEAN NOT NULL DEFAULT false,
    "lastLoginAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefreshToken" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "deviceId" TEXT,
    "ipAddress" TEXT,
    "userAgent" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "replacedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RefreshToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Character" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" VARCHAR(16) NOT NULL,
    "nameNormalized" TEXT NOT NULL,
    "classType" "CharacterClass" NOT NULL,
    "gender" "Gender" NOT NULL DEFAULT 'NEUTRAL',
    "faction" "Faction" NOT NULL DEFAULT 'UNALIGNED',
    "region" "Region" NOT NULL DEFAULT 'SA',
    "shardId" TEXT NOT NULL DEFAULT 'sa-gru-1',
    "level" INTEGER NOT NULL DEFAULT 1,
    "experience" BIGINT NOT NULL DEFAULT 0,
    "currentMapId" TEXT NOT NULL DEFAULT 'solhaven_plaza',
    "positionX" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "positionY" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "positionZ" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "rotationY" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "currentHp" INTEGER NOT NULL DEFAULT 100,
    "currentRes" INTEGER NOT NULL DEFAULT 50,
    "playTimeSec" INTEGER NOT NULL DEFAULT 0,
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Character_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CharacterAttributes" (
    "characterId" TEXT NOT NULL,
    "strength" INTEGER NOT NULL DEFAULT 10,
    "agility" INTEGER NOT NULL DEFAULT 10,
    "intelligence" INTEGER NOT NULL DEFAULT 10,
    "vitality" INTEGER NOT NULL DEFAULT 10,
    "unspentPoints" INTEGER NOT NULL DEFAULT 0,
    "totalSpent" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "CharacterAttributes_pkey" PRIMARY KEY ("characterId")
);

-- CreateTable
CREATE TABLE "ItemDefinition" (
    "id" VARCHAR(64) NOT NULL,
    "category" "ItemCategory" NOT NULL,
    "rarity" "ItemRarity" NOT NULL,
    "equipSlot" "EquipSlot",
    "requiredLevel" INTEGER NOT NULL DEFAULT 1,
    "requiredClass" "CharacterClass",
    "maxStack" INTEGER NOT NULL DEFAULT 1,
    "baseValue" INTEGER NOT NULL DEFAULT 0,
    "isTradeable" BOOLEAN NOT NULL DEFAULT true,
    "isBindOnPickup" BOOLEAN NOT NULL DEFAULT false,
    "iconAddress" TEXT NOT NULL,
    "modelAddress" TEXT,
    "baseStats" JSONB NOT NULL DEFAULT '{}',
    "affixSlots" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ItemDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ItemInstance" (
    "id" TEXT NOT NULL,
    "definitionId" VARCHAR(64) NOT NULL,
    "ownerCharacterId" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "upgradeLevel" INTEGER NOT NULL DEFAULT 0,
    "rolledStats" JSONB NOT NULL DEFAULT '{}',
    "affixes" JSONB NOT NULL DEFAULT '[]',
    "isLocked" BOOLEAN NOT NULL DEFAULT false,
    "sourceRunId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ItemInstance_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InventorySlot" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "slotIndex" INTEGER NOT NULL,
    "itemInstanceId" TEXT NOT NULL,

    CONSTRAINT "InventorySlot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EquipmentSlot" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "slot" "EquipSlot" NOT NULL,
    "itemInstanceId" TEXT NOT NULL,

    CONSTRAINT "EquipmentSlot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SkillDefinition" (
    "id" VARCHAR(64) NOT NULL,
    "classType" "CharacterClass" NOT NULL,
    "requiredLevel" INTEGER NOT NULL DEFAULT 1,
    "maxRank" INTEGER NOT NULL DEFAULT 5,
    "resourceCost" INTEGER NOT NULL DEFAULT 0,
    "cooldownMs" INTEGER NOT NULL DEFAULT 1000,
    "castTimeMs" INTEGER NOT NULL DEFAULT 0,
    "rangeMeters" DOUBLE PRECISION NOT NULL DEFAULT 3,
    "scaling" JSONB NOT NULL DEFAULT '{}',
    "iconAddress" TEXT NOT NULL,
    "vfxAddress" TEXT,
    "isUltimate" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "SkillDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CharacterSkill" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "skillId" VARCHAR(64) NOT NULL,
    "rank" INTEGER NOT NULL DEFAULT 1,
    "hotbarSlot" INTEGER,

    CONSTRAINT "CharacterSkill_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MonsterDefinition" (
    "id" VARCHAR(64) NOT NULL,
    "tier" INTEGER NOT NULL DEFAULT 1,
    "baseLevel" INTEGER NOT NULL DEFAULT 1,
    "baseHp" INTEGER NOT NULL,
    "baseDamage" INTEGER NOT NULL,
    "baseArmor" INTEGER NOT NULL DEFAULT 0,
    "moveSpeed" DOUBLE PRECISION NOT NULL DEFAULT 3.0,
    "aggroRadius" DOUBLE PRECISION NOT NULL DEFAULT 8.0,
    "xpReward" INTEGER NOT NULL DEFAULT 10,
    "lootTableId" TEXT,
    "modelAddress" TEXT NOT NULL,
    "aiPattern" JSONB NOT NULL DEFAULT '[]',

    CONSTRAINT "MonsterDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LootTable" (
    "id" VARCHAR(64) NOT NULL,
    "goldMin" INTEGER NOT NULL DEFAULT 0,
    "goldMax" INTEGER NOT NULL DEFAULT 0,
    "maxDrops" INTEGER NOT NULL DEFAULT 3,

    CONSTRAINT "LootTable_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LootEntry" (
    "id" TEXT NOT NULL,
    "lootTableId" VARCHAR(64) NOT NULL,
    "itemDefId" VARCHAR(64) NOT NULL,
    "weight" INTEGER NOT NULL DEFAULT 100,
    "minQuantity" INTEGER NOT NULL DEFAULT 1,
    "maxQuantity" INTEGER NOT NULL DEFAULT 1,
    "minDifficulty" "Difficulty" NOT NULL DEFAULT 'NORMAL',

    CONSTRAINT "LootEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DungeonDefinition" (
    "id" VARCHAR(64) NOT NULL,
    "zoneId" VARCHAR(64) NOT NULL,
    "minLevel" INTEGER NOT NULL DEFAULT 1,
    "maxPlayers" INTEGER NOT NULL DEFAULT 4,
    "difficulty" "Difficulty" NOT NULL DEFAULT 'NORMAL',
    "estimatedMin" INTEGER NOT NULL DEFAULT 8,
    "dailyRunLimit" INTEGER NOT NULL DEFAULT 3,
    "bossMonsterId" VARCHAR(64),
    "layoutConfig" JSONB NOT NULL DEFAULT '{}',
    "lootTableId" VARCHAR(64),

    CONSTRAINT "DungeonDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DungeonRun" (
    "id" TEXT NOT NULL,
    "dungeonId" VARCHAR(64) NOT NULL,
    "characterId" TEXT NOT NULL,
    "partyKey" TEXT,
    "seed" BIGINT NOT NULL,
    "difficulty" "Difficulty" NOT NULL DEFAULT 'NORMAL',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "wasCleared" BOOLEAN NOT NULL DEFAULT false,
    "deaths" INTEGER NOT NULL DEFAULT 0,
    "damageDealt" BIGINT NOT NULL DEFAULT 0,
    "durationSec" INTEGER,

    CONSTRAINT "DungeonRun_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "QuestDefinition" (
    "id" VARCHAR(64) NOT NULL,
    "questType" "QuestType" NOT NULL,
    "zoneId" VARCHAR(64),
    "requiredLevel" INTEGER NOT NULL DEFAULT 1,
    "prerequisiteId" VARCHAR(64),
    "objectives" JSONB NOT NULL DEFAULT '[]',
    "rewards" JSONB NOT NULL DEFAULT '{}',
    "isRepeatable" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "QuestDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "QuestProgress" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "questId" VARCHAR(64) NOT NULL,
    "state" "QuestState" NOT NULL DEFAULT 'ACTIVE',
    "counters" JSONB NOT NULL DEFAULT '{}',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "claimedAt" TIMESTAMP(3),
    "resetAt" TIMESTAMP(3),

    CONSTRAINT "QuestProgress_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EconomyLedger" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "currency" "CurrencyType" NOT NULL,
    "amount" BIGINT NOT NULL,
    "balanceAfter" BIGINT NOT NULL,
    "operation" "LedgerOperation" NOT NULL,
    "referenceId" TEXT,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "EconomyLedger_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WalletBalance" (
    "characterId" TEXT NOT NULL,
    "currency" "CurrencyType" NOT NULL,
    "amount" BIGINT NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "WalletBalance_pkey" PRIMARY KEY ("characterId","currency")
);

-- CreateTable
CREATE TABLE "PaymentOrder" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "characterId" TEXT,
    "provider" "PaymentProvider" NOT NULL,
    "providerEventId" TEXT NOT NULL,
    "providerOrderId" TEXT,
    "productSku" VARCHAR(64) NOT NULL,
    "amountCents" INTEGER NOT NULL,
    "currencyCode" VARCHAR(3) NOT NULL,
    "countryCode" VARCHAR(2) NOT NULL,
    "gemsGranted" INTEGER NOT NULL DEFAULT 0,
    "status" "PaymentStatus" NOT NULL DEFAULT 'PENDING',
    "rawPayload" JSONB,
    "paidAt" TIMESTAMP(3),
    "creditedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PaymentOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MarketListing" (
    "id" TEXT NOT NULL,
    "sellerId" TEXT NOT NULL,
    "itemInstanceId" TEXT NOT NULL,
    "priceGold" BIGINT NOT NULL,
    "state" "MarketState" NOT NULL DEFAULT 'ACTIVE',
    "buyerId" TEXT,
    "listedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "soldAt" TIMESTAMP(3),

    CONSTRAINT "MarketListing_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Guild" (
    "id" TEXT NOT NULL,
    "name" VARCHAR(24) NOT NULL,
    "nameNormalized" TEXT NOT NULL,
    "tag" VARCHAR(5) NOT NULL,
    "descriptionRaw" VARCHAR(280),
    "emblemId" TEXT NOT NULL DEFAULT 'emblem_01',
    "level" INTEGER NOT NULL DEFAULT 1,
    "experience" BIGINT NOT NULL DEFAULT 0,
    "treasuryGold" BIGINT NOT NULL DEFAULT 0,
    "maxMembers" INTEGER NOT NULL DEFAULT 30,
    "faction" "Faction" NOT NULL DEFAULT 'UNALIGNED',
    "shardId" TEXT NOT NULL DEFAULT 'sa-gru-1',
    "isRecruiting" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Guild_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuildMember" (
    "characterId" TEXT NOT NULL,
    "guildId" TEXT NOT NULL,
    "rank" "GuildRank" NOT NULL DEFAULT 'MEMBER',
    "contribution" BIGINT NOT NULL DEFAULT 0,
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuildMember_pkey" PRIMARY KEY ("characterId")
);

-- CreateTable
CREATE TABLE "Friendship" (
    "id" TEXT NOT NULL,
    "fromId" TEXT NOT NULL,
    "toId" TEXT NOT NULL,
    "state" "FriendshipState" NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Friendship_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MailMessage" (
    "id" TEXT NOT NULL,
    "recipientId" TEXT NOT NULL,
    "senderId" TEXT,
    "subjectKey" VARCHAR(80) NOT NULL,
    "bodyKey" VARCHAR(80) NOT NULL,
    "bodyParams" JSONB NOT NULL DEFAULT '{}',
    "freeTextBody" VARCHAR(500),
    "attachedGold" BIGINT NOT NULL DEFAULT 0,
    "attachedGems" BIGINT NOT NULL DEFAULT 0,
    "attachedItems" JSONB NOT NULL DEFAULT '[]',
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "isClaimed" BOOLEAN NOT NULL DEFAULT false,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MailMessage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Companion" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "definitionId" VARCHAR(64) NOT NULL,
    "level" INTEGER NOT NULL DEFAULT 1,
    "starRank" INTEGER NOT NULL DEFAULT 1,
    "isActive" BOOLEAN NOT NULL DEFAULT false,
    "acquiredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Companion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Familiar" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "definitionId" VARCHAR(64) NOT NULL,
    "nickname" VARCHAR(16),
    "level" INTEGER NOT NULL DEFAULT 1,
    "isActive" BOOLEAN NOT NULL DEFAULT false,
    "acquiredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Familiar_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EventDefinition" (
    "id" TEXT NOT NULL,
    "titleKey" VARCHAR(80) NOT NULL,
    "descriptionKey" VARCHAR(80) NOT NULL,
    "frequencyType" VARCHAR(16) NOT NULL,
    "difficultyTier" "Difficulty" NOT NULL DEFAULT 'NORMAL',
    "rewardsPayload" JSONB NOT NULL DEFAULT '{}',
    "countryFilter" JSONB,
    "minLevel" INTEGER NOT NULL DEFAULT 1,
    "startsAt" TIMESTAMP(3) NOT NULL,
    "endsAt" TIMESTAMP(3) NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "EventDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EventProgression" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "eventDefinitionId" TEXT NOT NULL,
    "score" INTEGER NOT NULL DEFAULT 0,
    "completedTiers" JSONB NOT NULL DEFAULT '[]',
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "EventProgression_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LocalizedString" (
    "key" VARCHAR(120) NOT NULL,
    "locale" "Locale" NOT NULL,
    "value" TEXT NOT NULL,
    "context" VARCHAR(200),
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LocalizedString_pkey" PRIMARY KEY ("key","locale")
);

-- CreateTable
CREATE TABLE "AuditLog" (
    "id" TEXT NOT NULL,
    "actorType" VARCHAR(16) NOT NULL,
    "actorId" TEXT,
    "action" VARCHAR(64) NOT NULL,
    "targetType" VARCHAR(32),
    "targetId" TEXT,
    "before" JSONB,
    "after" JSONB,
    "reason" VARCHAR(280),
    "ipAddress" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Sanction" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "SanctionType" NOT NULL,
    "reasonKey" VARCHAR(80) NOT NULL,
    "internalNote" VARCHAR(500),
    "issuedBy" TEXT,
    "startsAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Sanction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE INDEX "User_countryCode_idx" ON "User"("countryCode");

-- CreateIndex
CREATE INDEX "User_createdAt_idx" ON "User"("createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "RefreshToken_tokenHash_key" ON "RefreshToken"("tokenHash");

-- CreateIndex
CREATE INDEX "RefreshToken_userId_revokedAt_idx" ON "RefreshToken"("userId", "revokedAt");

-- CreateIndex
CREATE INDEX "RefreshToken_expiresAt_idx" ON "RefreshToken"("expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "Character_name_key" ON "Character"("name");

-- CreateIndex
CREATE UNIQUE INDEX "Character_nameNormalized_key" ON "Character"("nameNormalized");

-- CreateIndex
CREATE INDEX "Character_userId_idx" ON "Character"("userId");

-- CreateIndex
CREATE INDEX "Character_shardId_level_idx" ON "Character"("shardId", "level");

-- CreateIndex
CREATE INDEX "Character_faction_level_idx" ON "Character"("faction", "level");

-- CreateIndex
CREATE INDEX "Character_lastSeenAt_idx" ON "Character"("lastSeenAt");

-- CreateIndex
CREATE INDEX "ItemDefinition_category_rarity_idx" ON "ItemDefinition"("category", "rarity");

-- CreateIndex
CREATE INDEX "ItemDefinition_requiredLevel_idx" ON "ItemDefinition"("requiredLevel");

-- CreateIndex
CREATE INDEX "ItemInstance_ownerCharacterId_idx" ON "ItemInstance"("ownerCharacterId");

-- CreateIndex
CREATE INDEX "ItemInstance_definitionId_idx" ON "ItemInstance"("definitionId");

-- CreateIndex
CREATE UNIQUE INDEX "InventorySlot_itemInstanceId_key" ON "InventorySlot"("itemInstanceId");

-- CreateIndex
CREATE INDEX "InventorySlot_characterId_idx" ON "InventorySlot"("characterId");

-- CreateIndex
CREATE UNIQUE INDEX "InventorySlot_characterId_slotIndex_key" ON "InventorySlot"("characterId", "slotIndex");

-- CreateIndex
CREATE UNIQUE INDEX "EquipmentSlot_itemInstanceId_key" ON "EquipmentSlot"("itemInstanceId");

-- CreateIndex
CREATE UNIQUE INDEX "EquipmentSlot_characterId_slot_key" ON "EquipmentSlot"("characterId", "slot");

-- CreateIndex
CREATE INDEX "SkillDefinition_classType_requiredLevel_idx" ON "SkillDefinition"("classType", "requiredLevel");

-- CreateIndex
CREATE UNIQUE INDEX "CharacterSkill_characterId_skillId_key" ON "CharacterSkill"("characterId", "skillId");

-- CreateIndex
CREATE UNIQUE INDEX "CharacterSkill_characterId_hotbarSlot_key" ON "CharacterSkill"("characterId", "hotbarSlot");

-- CreateIndex
CREATE INDEX "MonsterDefinition_tier_baseLevel_idx" ON "MonsterDefinition"("tier", "baseLevel");

-- CreateIndex
CREATE INDEX "LootEntry_lootTableId_idx" ON "LootEntry"("lootTableId");

-- CreateIndex
CREATE INDEX "DungeonDefinition_zoneId_minLevel_idx" ON "DungeonDefinition"("zoneId", "minLevel");

-- CreateIndex
CREATE INDEX "DungeonRun_characterId_startedAt_idx" ON "DungeonRun"("characterId", "startedAt");

-- CreateIndex
CREATE INDEX "DungeonRun_partyKey_idx" ON "DungeonRun"("partyKey");

-- CreateIndex
CREATE INDEX "DungeonRun_dungeonId_completedAt_idx" ON "DungeonRun"("dungeonId", "completedAt");

-- CreateIndex
CREATE INDEX "QuestDefinition_questType_requiredLevel_idx" ON "QuestDefinition"("questType", "requiredLevel");

-- CreateIndex
CREATE INDEX "QuestDefinition_zoneId_idx" ON "QuestDefinition"("zoneId");

-- CreateIndex
CREATE INDEX "QuestProgress_characterId_state_idx" ON "QuestProgress"("characterId", "state");

-- CreateIndex
CREATE UNIQUE INDEX "QuestProgress_characterId_questId_key" ON "QuestProgress"("characterId", "questId");

-- CreateIndex
CREATE INDEX "EconomyLedger_characterId_currency_createdAt_idx" ON "EconomyLedger"("characterId", "currency", "createdAt");

-- CreateIndex
CREATE INDEX "EconomyLedger_operation_createdAt_idx" ON "EconomyLedger"("operation", "createdAt");

-- CreateIndex
CREATE INDEX "EconomyLedger_referenceId_idx" ON "EconomyLedger"("referenceId");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentOrder_providerEventId_key" ON "PaymentOrder"("providerEventId");

-- CreateIndex
CREATE INDEX "PaymentOrder_userId_status_idx" ON "PaymentOrder"("userId", "status");

-- CreateIndex
CREATE INDEX "PaymentOrder_status_createdAt_idx" ON "PaymentOrder"("status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "MarketListing_itemInstanceId_key" ON "MarketListing"("itemInstanceId");

-- CreateIndex
CREATE INDEX "MarketListing_state_priceGold_idx" ON "MarketListing"("state", "priceGold");

-- CreateIndex
CREATE INDEX "MarketListing_sellerId_state_idx" ON "MarketListing"("sellerId", "state");

-- CreateIndex
CREATE INDEX "MarketListing_expiresAt_idx" ON "MarketListing"("expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "Guild_name_key" ON "Guild"("name");

-- CreateIndex
CREATE UNIQUE INDEX "Guild_nameNormalized_key" ON "Guild"("nameNormalized");

-- CreateIndex
CREATE UNIQUE INDEX "Guild_tag_key" ON "Guild"("tag");

-- CreateIndex
CREATE INDEX "Guild_shardId_level_idx" ON "Guild"("shardId", "level");

-- CreateIndex
CREATE INDEX "GuildMember_guildId_rank_idx" ON "GuildMember"("guildId", "rank");

-- CreateIndex
CREATE INDEX "Friendship_toId_state_idx" ON "Friendship"("toId", "state");

-- CreateIndex
CREATE UNIQUE INDEX "Friendship_fromId_toId_key" ON "Friendship"("fromId", "toId");

-- CreateIndex
CREATE INDEX "MailMessage_recipientId_isRead_idx" ON "MailMessage"("recipientId", "isRead");

-- CreateIndex
CREATE INDEX "MailMessage_expiresAt_idx" ON "MailMessage"("expiresAt");

-- CreateIndex
CREATE INDEX "Companion_characterId_isActive_idx" ON "Companion"("characterId", "isActive");

-- CreateIndex
CREATE UNIQUE INDEX "Companion_characterId_definitionId_key" ON "Companion"("characterId", "definitionId");

-- CreateIndex
CREATE UNIQUE INDEX "Familiar_characterId_definitionId_key" ON "Familiar"("characterId", "definitionId");

-- CreateIndex
CREATE INDEX "EventDefinition_isActive_startsAt_endsAt_idx" ON "EventDefinition"("isActive", "startsAt", "endsAt");

-- CreateIndex
CREATE INDEX "EventProgression_eventDefinitionId_score_idx" ON "EventProgression"("eventDefinitionId", "score");

-- CreateIndex
CREATE UNIQUE INDEX "EventProgression_characterId_eventDefinitionId_key" ON "EventProgression"("characterId", "eventDefinitionId");

-- CreateIndex
CREATE INDEX "LocalizedString_locale_idx" ON "LocalizedString"("locale");

-- CreateIndex
CREATE INDEX "AuditLog_actorId_createdAt_idx" ON "AuditLog"("actorId", "createdAt");

-- CreateIndex
CREATE INDEX "AuditLog_targetType_targetId_idx" ON "AuditLog"("targetType", "targetId");

-- CreateIndex
CREATE INDEX "AuditLog_action_createdAt_idx" ON "AuditLog"("action", "createdAt");

-- CreateIndex
CREATE INDEX "Sanction_userId_isActive_idx" ON "Sanction"("userId", "isActive");

-- CreateIndex
CREATE INDEX "Sanction_expiresAt_idx" ON "Sanction"("expiresAt");

-- AddForeignKey
ALTER TABLE "RefreshToken" ADD CONSTRAINT "RefreshToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Character" ADD CONSTRAINT "Character_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CharacterAttributes" ADD CONSTRAINT "CharacterAttributes_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ItemInstance" ADD CONSTRAINT "ItemInstance_definitionId_fkey" FOREIGN KEY ("definitionId") REFERENCES "ItemDefinition"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ItemInstance" ADD CONSTRAINT "ItemInstance_ownerCharacterId_fkey" FOREIGN KEY ("ownerCharacterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventorySlot" ADD CONSTRAINT "InventorySlot_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventorySlot" ADD CONSTRAINT "InventorySlot_itemInstanceId_fkey" FOREIGN KEY ("itemInstanceId") REFERENCES "ItemInstance"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EquipmentSlot" ADD CONSTRAINT "EquipmentSlot_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EquipmentSlot" ADD CONSTRAINT "EquipmentSlot_itemInstanceId_fkey" FOREIGN KEY ("itemInstanceId") REFERENCES "ItemInstance"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CharacterSkill" ADD CONSTRAINT "CharacterSkill_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CharacterSkill" ADD CONSTRAINT "CharacterSkill_skillId_fkey" FOREIGN KEY ("skillId") REFERENCES "SkillDefinition"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MonsterDefinition" ADD CONSTRAINT "MonsterDefinition_lootTableId_fkey" FOREIGN KEY ("lootTableId") REFERENCES "LootTable"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LootEntry" ADD CONSTRAINT "LootEntry_lootTableId_fkey" FOREIGN KEY ("lootTableId") REFERENCES "LootTable"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LootEntry" ADD CONSTRAINT "LootEntry_itemDefId_fkey" FOREIGN KEY ("itemDefId") REFERENCES "ItemDefinition"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DungeonRun" ADD CONSTRAINT "DungeonRun_dungeonId_fkey" FOREIGN KEY ("dungeonId") REFERENCES "DungeonDefinition"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DungeonRun" ADD CONSTRAINT "DungeonRun_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "QuestProgress" ADD CONSTRAINT "QuestProgress_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "QuestProgress" ADD CONSTRAINT "QuestProgress_questId_fkey" FOREIGN KEY ("questId") REFERENCES "QuestDefinition"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EconomyLedger" ADD CONSTRAINT "EconomyLedger_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WalletBalance" ADD CONSTRAINT "WalletBalance_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PaymentOrder" ADD CONSTRAINT "PaymentOrder_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MarketListing" ADD CONSTRAINT "MarketListing_sellerId_fkey" FOREIGN KEY ("sellerId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MarketListing" ADD CONSTRAINT "MarketListing_itemInstanceId_fkey" FOREIGN KEY ("itemInstanceId") REFERENCES "ItemInstance"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuildMember" ADD CONSTRAINT "GuildMember_guildId_fkey" FOREIGN KEY ("guildId") REFERENCES "Guild"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuildMember" ADD CONSTRAINT "GuildMember_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Friendship" ADD CONSTRAINT "Friendship_fromId_fkey" FOREIGN KEY ("fromId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Friendship" ADD CONSTRAINT "Friendship_toId_fkey" FOREIGN KEY ("toId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MailMessage" ADD CONSTRAINT "MailMessage_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MailMessage" ADD CONSTRAINT "MailMessage_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "Character"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Companion" ADD CONSTRAINT "Companion_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Familiar" ADD CONSTRAINT "Familiar_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EventProgression" ADD CONSTRAINT "EventProgression_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EventProgression" ADD CONSTRAINT "EventProgression_eventDefinitionId_fkey" FOREIGN KEY ("eventDefinitionId") REFERENCES "EventDefinition"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Sanction" ADD CONSTRAINT "Sanction_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
