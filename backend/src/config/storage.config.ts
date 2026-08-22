import { registerAs } from "@nestjs/config";

function endpointToParts(endpoint: string): { host: string; port: number; useSSL: boolean } {
  const url = new URL(endpoint);
  const useSSL = url.protocol === "https:";
  return {
    host: url.hostname,
    port: Number(url.port || (useSSL ? 443 : 80)),
    useSSL,
  };
}

export default registerAs("storage", () => {
  const parts = endpointToParts(process.env.STORAGE_ENDPOINT ?? "http://localhost:9000");
  return {
    endpoint: process.env.STORAGE_ENDPOINT ?? "http://localhost:9000",
    host: parts.host,
    port: parts.port,
    useSSL: parts.useSSL,
    accessKey: process.env.STORAGE_ACCESS_KEY ?? "",
    secretKey: process.env.STORAGE_SECRET_KEY ?? "",
    bucket: process.env.STORAGE_BUCKET ?? "vet-docs",
    region: process.env.STORAGE_REGION ?? "us-east-1",
    uploadTtl: Number(process.env.STORAGE_UPLOAD_TICKET_TTL_SECONDS ?? 600),
    downloadTtl: Number(process.env.STORAGE_DOWNLOAD_TICKET_TTL_SECONDS ?? 300),
  };
});
