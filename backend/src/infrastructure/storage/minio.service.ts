import { Injectable, Logger, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Client as MinioClient, BucketItemStat } from "minio";

@Injectable()
export class MinioService implements OnModuleInit {
  private readonly logger = new Logger(MinioService.name);
  private client!: MinioClient;
  private bucket!: string;
  private uploadTtl!: number;
  private downloadTtl!: number;

  constructor(private readonly config: ConfigService) {}

  async onModuleInit(): Promise<void> {
    const endpoint = this.config.get<string>("STORAGE_ENDPOINT") ?? "http://localhost:9000";
    const url = new URL(endpoint);
    this.bucket = this.config.get<string>("STORAGE_BUCKET") ?? "vet-docs";
    this.uploadTtl = Number(this.config.get<string>("STORAGE_UPLOAD_TICKET_TTL_SECONDS") ?? 600);
    this.downloadTtl = Number(this.config.get<string>("STORAGE_DOWNLOAD_TICKET_TTL_SECONDS") ?? 300);

    this.client = new MinioClient({
      endPoint: url.hostname,
      port: Number(url.port || (url.protocol === "https:" ? 443 : 80)),
      useSSL: url.protocol === "https:",
      accessKey: this.config.get<string>("STORAGE_ACCESS_KEY") ?? "",
      secretKey: this.config.get<string>("STORAGE_SECRET_KEY") ?? "",
      region: this.config.get<string>("STORAGE_REGION") ?? "us-east-1",
    });

    try {
      const exists = await this.client.bucketExists(this.bucket);
      if (!exists) {
        await this.client.makeBucket(this.bucket, this.config.get<string>("STORAGE_REGION") ?? "us-east-1");
        this.logger.log(`Bucket creado: ${this.bucket}`);
      }
    } catch (err: any) {
      this.logger.warn(`MinIO no accesible al iniciar: ${err?.message}`);
    }
  }

  getBucket(): string {
    return this.bucket;
  }

  buildKey(empresaId: string | null, area: string, filename: string): string {
    const safe = filename.replace(/[^a-zA-Z0-9._-]/g, "_");
    const yyyymm = new Date().toISOString().slice(0, 7).replace("-", "/");
    const prefix = empresaId ? `e_${empresaId}` : "global";
    return `${prefix}/${area}/${yyyymm}/${Date.now()}_${safe}`;
  }

  async presignedUploadUrl(objectKey: string): Promise<{ url: string; expiresIn: number }> {
    const url = await this.client.presignedPutObject(this.bucket, objectKey, this.uploadTtl);
    return { url, expiresIn: this.uploadTtl };
  }

  /**
   * Sube un buffer directamente (el backend recibe el archivo y lo empuja a
   * MinIO). Se usa cuando el cliente NO debe alcanzar MinIO directamente, p.ej.
   * la subida pública del proveedor por magic-link.
   */
  async putObject(objectKey: string, buffer: Buffer, contentType?: string): Promise<void> {
    await this.client.putObject(
      this.bucket,
      objectKey,
      buffer,
      buffer.length,
      contentType ? { "Content-Type": contentType } : undefined,
    );
  }

  async presignedDownloadUrl(objectKey: string): Promise<{ url: string; expiresIn: number }> {
    const url = await this.client.presignedGetObject(this.bucket, objectKey, this.downloadTtl);
    return { url, expiresIn: this.downloadTtl };
  }

  async statObject(objectKey: string): Promise<BucketItemStat> {
    return this.client.statObject(this.bucket, objectKey);
  }

  async deleteObject(objectKey: string): Promise<void> {
    await this.client.removeObject(this.bucket, objectKey);
  }

  async ping(): Promise<boolean> {
    try {
      await this.client.bucketExists(this.bucket);
      return true;
    } catch {
      return false;
    }
  }
}
