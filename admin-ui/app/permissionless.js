import { getAddress } from "viem";
import { erc20MetadataAbi, MAX_UINT256 } from "./config.js";
import { requirePermissionlessWallet, writePermissionlessToken } from "./chain.js";
import { state } from "./state.js";

export async function ensurePermissionlessTokenApprovals(tokens) {
  requirePermissionlessWallet();
  const uniqueTokens = [...new Set(tokens.filter(Boolean).map((token) => getAddress(token)))];
  for (const token of uniqueTokens) await ensurePermissionlessTokenApproval(token);
}

async function ensurePermissionlessTokenApproval(token) {
  const allowance = await state.publicClient.readContract({
    address: token,
    abi: erc20MetadataAbi,
    functionName: "allowance",
    args: [state.permissionlessAccount, state.diamondAddress],
  });
  if (allowance === MAX_UINT256) return;
  if (allowance > 0n) {
    await writePermissionlessToken(token, erc20MetadataAbi, "approve", [state.diamondAddress, 0n]);
  }
  await writePermissionlessToken(token, erc20MetadataAbi, "approve", [state.diamondAddress, MAX_UINT256]);
}
