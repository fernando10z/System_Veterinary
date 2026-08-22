import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import * as crypto from "crypto";

/**
 * Cifrado simétrico para secretos en reposo (p. ej. contraseñas SMTP por usuario).
 * AES-256-GCM. La llave se deriva de ENCRYPTION_KEY vía SHA-256 (32 bytes), así
 * funciona sea cual sea el formato/longitud de la variable.
 * Formato del blob: base64(iv):base64(authTag):base64(ciphertext)
 */
@Injectable()
export class CryptoService {
  private readonly key: Buffer;

  constructor(config: ConfigService) {
    const secret = config.get<string>("ENCRYPTION_KEY") ?? "";
    this.key = crypto.createHash("sha256").update(secret).digest();
  }

  encrypt(plain: string): string {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv("aes-256-gcm", this.key, iv);
    const enc = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return [iv.toString("base64"), tag.toString("base64"), enc.toString("base64")].join(":");
  }

  decrypt(blob: string): string {
    const [ivB, tagB, dataB] = blob.split(":");
    if (!ivB || !tagB || !dataB) {
      throw new Error("Blob cifrado inválido");
    }
    const decipher = crypto.createDecipheriv("aes-256-gcm", this.key, Buffer.from(ivB, "base64"));
    decipher.setAuthTag(Buffer.from(tagB, "base64"));
    const dec = Buffer.concat([decipher.update(Buffer.from(dataB, "base64")), decipher.final()]);
    return dec.toString("utf8");
  }
}
