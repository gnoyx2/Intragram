// Accepted files reserve their declared size before the first chunk arrives.
// This applies across every peer in a hosted room, not just completed blobs.
export function receiveBudget(transfers) {
  let bytes = 0, files = 0;
  for (const transfer of transfers) {
    if (transfer.direction === 'receive' && (transfer.blob || transfer.state === 'transferring')) {
      bytes += transfer.size;
      files++;
    }
  }
  return { bytes, files };
}
