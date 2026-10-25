import { Injectable, Logger, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Client as MinioClient, BucketItemStat } from "minio";
import { Readable } from "stream";

function clienteDesde(endpoint: string, accessKey: string, secretKey: string, region: string) {
  const url = new URL(endpoint);
  if (url.pathname && url.pathname !== "/") {
    // MinIO/S3 en estilo path no admite un prefijo delante del bucket.
    throw new Error(`El endpoint de almacenamiento no puede llevar ruta: ${endpoint}`);
  }
  return new MinioClient({
    endPoint: url.hostname,
    port: Number(url.port || (url.protocol === "https:" ? 443 : 80)),
    useSSL: url.protocol === "https:",
    accessKey,
    secretKey,
    // Con la región fijada, el cliente firma sin consultar al servidor: el
    // firmador público nunca abre conexiones.
    region,
  });
}

@Injectable()
export class MinioService implements OnModuleInit {
  private readonly logger = new Logger(MinioService.name);
  private client!: MinioClient;
  /**
   * Cliente que SOLO firma URLs. El backend habla con MinIO por la red interna
   * (http://minio:9000), pero una URL firmada contra ese host no la puede abrir
   * el navegador. STORAGE_PUBLIC_ENDPOINT es la dirección por la que el
   * navegador llega a MinIO —en el despliegue, el propio dominio: nginx
   * reenvía /<bucket>/ a MinIO conservando el Host, que es parte de la firma—.
   */
  private firmador!: MinioClient;
  private bucket!: string;
  private uploadTtl!: number;
  private downloadTtl!: number;

  constructor(private readonly config: ConfigService) {}

  async onModuleInit(): Promise<void> {
    const endpoint = this.config.get<string>("STORAGE_ENDPOINT") ?? "http://localhost:9000";
    const publico = this.config.get<string>("STORAGE_PUBLIC_ENDPOINT") || endpoint;
    const accessKey = this.config.get<string>("STORAGE_ACCESS_KEY") ?? "";
    const secretKey = this.config.get<string>("STORAGE_SECRET_KEY") ?? "";
    const region = this.config.get<string>("STORAGE_REGION") ?? "us-east-1";
    this.bucket = this.config.get<string>("STORAGE_BUCKET") ?? "vet-docs";
    this.uploadTtl = Number(this.config.get<string>("STORAGE_UPLOAD_TICKET_TTL_SECONDS") ?? 600);
    this.downloadTtl = Number(this.config.get<string>("STORAGE_DOWNLOAD_TICKET_TTL_SECONDS") ?? 300);

    this.client = clienteDesde(endpoint, accessKey, secretKey, region);
    this.firmador = publico === endpoint
      ? this.client
      : clienteDesde(publico, accessKey, secretKey, region);

    try {
      const exists = await this.client.bucketExists(this.bucket);
      if (!exists) {
        await this.client.makeBucket(this.bucket, region);
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

  /**
   * Ticket de subida directa: POST con política firmada, no PUT prefirmado. El
   * PUT firmado solo fija la clave; el navegador podía mandar cualquier tipo y
   * cualquier tamaño. La política obliga en el propio MinIO a la clave exacta,
   * al Content-Type exacto y a un tamaño entre 1 byte y `maxBytes`.
   */
  async presignedUploadPost(
    objectKey: string,
    contentType: string,
    maxBytes: number,
  ): Promise<{ url: string; campos: Record<string, string>; expiresIn: number }> {
    const policy = this.firmador.newPostPolicy();
    policy.setBucket(this.bucket);
    policy.setKey(objectKey);
    policy.setContentType(contentType);
    policy.setContentLengthRange(1, maxBytes);
    policy.setExpires(new Date(Date.now() + this.uploadTtl * 1000));
    const r = await this.firmador.presignedPostPolicy(policy);
    return { url: r.postURL, campos: r.formData, expiresIn: this.uploadTtl };
  }

  /**
   * Sube un stream sin conocer el tamaño de antemano (MinIO lo parte en
   * multipart). El backend no carga el archivo entero en memoria: con 50 MB
   * por archivo y varias subidas a la vez, `toBuffer()` era la forma más
   * barata de tumbar el proceso.
   */
  async putObjectStream(objectKey: string, stream: Readable, contentType: string): Promise<void> {
    await this.client.putObject(this.bucket, objectKey, stream, undefined, {
      "Content-Type": contentType,
    });
  }

  async presignedDownloadUrl(objectKey: string): Promise<{ url: string; expiresIn: number }> {
    const url = await this.firmador.presignedGetObject(this.bucket, objectKey, this.downloadTtl);
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
