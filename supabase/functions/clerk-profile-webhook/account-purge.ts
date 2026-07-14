export type AccountStorageObject = {
  bucket_id: string;
  object_path: string;
};

type ServiceFetch = (path: string, init: RequestInit) => Promise<Response>;

export async function purgeAccountStorage(
  profileID: string,
  eventTimestamp: string,
  serviceFetch: ServiceFetch,
): Promise<number> {
  const inventoryResponse = await serviceFetch("/rest/v1/rpc/account_storage_objects", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ profile_id: profileID, event_timestamp: eventTimestamp }),
  });
  if (!inventoryResponse.ok) {
    throw new Error(`account_storage_inventory_failed:${inventoryResponse.status}:${await inventoryResponse.text()}`);
  }

  const objects = await inventoryResponse.json() as AccountStorageObject[];
  for (const object of objects) {
    const path = [object.bucket_id, ...object.object_path.split("/")]
      .map((part) => encodeURIComponent(part))
      .join("/");
    const deleteResponse = await serviceFetch(`/storage/v1/object/${path}`, { method: "DELETE" });
    if (!deleteResponse.ok && deleteResponse.status !== 404) {
      throw new Error(`account_storage_delete_failed:${deleteResponse.status}:${object.bucket_id}`);
    }
  }
  return objects.length;
}
