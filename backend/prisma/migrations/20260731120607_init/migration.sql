-- CreateEnum
CREATE TYPE "SubscriptionTier" AS ENUM ('free', 'premium');

-- CreateEnum
CREATE TYPE "FamilyRole" AS ENUM ('owner', 'member');

-- CreateEnum
CREATE TYPE "InviteStatus" AS ENUM ('pending', 'accepted', 'expired', 'revoked');

-- CreateEnum
CREATE TYPE "SlotType" AS ENUM ('breakfast', 'lunch', 'dinner', 'snack1', 'snack2', 'custom');

-- CreateEnum
CREATE TYPE "ProposalStatus" AS ENUM ('proposed', 'confirmed', 'locked');

-- CreateTable
CREATE TABLE "Family" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "subscriptionTier" "SubscriptionTier" NOT NULL DEFAULT 'free',
    "shoppingDays" INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Family_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "avatarUrl" TEXT,
    "familyId" TEXT,
    "role" "FamilyRole" NOT NULL DEFAULT 'member',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefreshToken" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RefreshToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Invite" (
    "id" TEXT NOT NULL,
    "familyId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "email" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "status" "InviteStatus" NOT NULL DEFAULT 'pending',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Invite_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MealTemplate" (
    "id" TEXT NOT NULL,
    "familyId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MealTemplate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MealTemplateSlotItem" (
    "id" TEXT NOT NULL,
    "templateId" TEXT NOT NULL,
    "slotType" "SlotType" NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "customLabel" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "MealTemplateSlotItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MealSlot" (
    "id" TEXT NOT NULL,
    "familyId" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "slotType" "SlotType" NOT NULL,
    "customLabel" TEXT,
    "isCustomSlot" BOOLEAN NOT NULL DEFAULT false,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MealSlot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MealProposal" (
    "id" TEXT NOT NULL,
    "mealSlotId" TEXT NOT NULL,
    "proposedByUserId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "photoUrl" TEXT,
    "status" "ProposalStatus" NOT NULL DEFAULT 'proposed',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MealProposal_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Vote" (
    "id" TEXT NOT NULL,
    "proposalId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Vote_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Comment" (
    "id" TEXT NOT NULL,
    "proposalId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Comment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ShoppingList" (
    "id" TEXT NOT NULL,
    "familyId" TEXT NOT NULL,
    "rangeStart" DATE NOT NULL,
    "rangeEnd" DATE NOT NULL,
    "generatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "generatedByAI" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "ShoppingList_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ShoppingListItem" (
    "id" TEXT NOT NULL,
    "shoppingListId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT,
    "quantity" TEXT,
    "buyByDate" DATE,
    "note" TEXT,
    "isChecked" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ShoppingListItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MealGalleryItem" (
    "id" TEXT NOT NULL,
    "familyId" TEXT,
    "title" TEXT NOT NULL,
    "photoUrl" TEXT NOT NULL,
    "category" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MealGalleryItem_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE INDEX "User_familyId_idx" ON "User"("familyId");

-- CreateIndex
CREATE UNIQUE INDEX "RefreshToken_tokenHash_key" ON "RefreshToken"("tokenHash");

-- CreateIndex
CREATE INDEX "RefreshToken_userId_idx" ON "RefreshToken"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "Invite_tokenHash_key" ON "Invite"("tokenHash");

-- CreateIndex
CREATE INDEX "Invite_familyId_idx" ON "Invite"("familyId");

-- CreateIndex
CREATE UNIQUE INDEX "MealTemplate_familyId_key" ON "MealTemplate"("familyId");

-- CreateIndex
CREATE INDEX "MealTemplateSlotItem_templateId_idx" ON "MealTemplateSlotItem"("templateId");

-- CreateIndex
CREATE UNIQUE INDEX "MealTemplateSlotItem_templateId_slotType_customLabel_key" ON "MealTemplateSlotItem"("templateId", "slotType", "customLabel");

-- CreateIndex
CREATE INDEX "MealSlot_familyId_date_idx" ON "MealSlot"("familyId", "date");

-- CreateIndex
CREATE UNIQUE INDEX "MealSlot_familyId_date_slotType_customLabel_key" ON "MealSlot"("familyId", "date", "slotType", "customLabel");

-- CreateIndex
CREATE INDEX "MealProposal_mealSlotId_idx" ON "MealProposal"("mealSlotId");

-- CreateIndex
CREATE INDEX "MealProposal_proposedByUserId_idx" ON "MealProposal"("proposedByUserId");

-- CreateIndex
CREATE INDEX "Vote_proposalId_idx" ON "Vote"("proposalId");

-- CreateIndex
CREATE UNIQUE INDEX "Vote_proposalId_userId_key" ON "Vote"("proposalId", "userId");

-- CreateIndex
CREATE INDEX "Comment_proposalId_idx" ON "Comment"("proposalId");

-- CreateIndex
CREATE INDEX "ShoppingList_familyId_idx" ON "ShoppingList"("familyId");

-- CreateIndex
CREATE INDEX "ShoppingListItem_shoppingListId_idx" ON "ShoppingListItem"("shoppingListId");

-- CreateIndex
CREATE INDEX "MealGalleryItem_familyId_idx" ON "MealGalleryItem"("familyId");

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefreshToken" ADD CONSTRAINT "RefreshToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Invite" ADD CONSTRAINT "Invite_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MealTemplate" ADD CONSTRAINT "MealTemplate_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MealTemplateSlotItem" ADD CONSTRAINT "MealTemplateSlotItem_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "MealTemplate"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MealSlot" ADD CONSTRAINT "MealSlot_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MealProposal" ADD CONSTRAINT "MealProposal_mealSlotId_fkey" FOREIGN KEY ("mealSlotId") REFERENCES "MealSlot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MealProposal" ADD CONSTRAINT "MealProposal_proposedByUserId_fkey" FOREIGN KEY ("proposedByUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Vote" ADD CONSTRAINT "Vote_proposalId_fkey" FOREIGN KEY ("proposalId") REFERENCES "MealProposal"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Vote" ADD CONSTRAINT "Vote_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Comment" ADD CONSTRAINT "Comment_proposalId_fkey" FOREIGN KEY ("proposalId") REFERENCES "MealProposal"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Comment" ADD CONSTRAINT "Comment_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShoppingList" ADD CONSTRAINT "ShoppingList_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShoppingListItem" ADD CONSTRAINT "ShoppingListItem_shoppingListId_fkey" FOREIGN KEY ("shoppingListId") REFERENCES "ShoppingList"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MealGalleryItem" ADD CONSTRAINT "MealGalleryItem_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
