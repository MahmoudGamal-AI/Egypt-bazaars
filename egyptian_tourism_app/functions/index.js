const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { Client } = require("pg");
const { GoogleGenerativeAI } = require("@google/generative-ai");

admin.initializeApp();

// ---------------------------------------------
// Database Configuration
// ---------------------------------------------
function getPgClient() {
    return new Client({
        host: process.env.AURORA_HOST,
        port: parseInt(process.env.AURORA_PORT || "5432"),
        database: process.env.AURORA_DB,
        user: process.env.AURORA_USER,
        password: process.env.AURORA_PASS,
        ssl: { rejectUnauthorized: false }
    });
}

// ---------------------------------------------
// Gemini Embeddings Setup
// ---------------------------------------------
const keysString = process.env.GEMINI_API_KEYS || "";
const GEMINI_KEYS = keysString.split(",").map(k => k.trim()).filter(k => k.length > 0);

async function getEmbedding(text) {
    if (GEMINI_KEYS.length === 0) throw new Error("No Gemini API keys provided");
    
    // Pick a random key for load balancing
    const randomKey = GEMINI_KEYS[Math.floor(Math.random() * GEMINI_KEYS.length)];
    const genAI = new GoogleGenerativeAI(randomKey);
    const model = genAI.getGenerativeModel({ model: "gemini-embedding-001" });
    
    const result = await model.embedContent(text);
    return result.embedding.values;
}

// Format vector array for Postgres pgvector, strictly ensuring 1536 dimensions
function formatVector(values) {
    let finalValues = values;
    if (values.length > 1536) {
        finalValues = values.slice(0, 1536);
    } else if (values.length < 1536) {
        finalValues = [...values, ...Array(1536 - values.length).fill(0)];
    }
    return `[${finalValues.join(",")}]`;
}

// Extract valid Date from Firestore Timestamp or string
function parseDate(val) {
    if (!val) return new Date();
    if (typeof val.toDate === "function") return val.toDate();
    return new Date(val);
}

// ---------------------------------------------
// 1. Sync Users
// ---------------------------------------------
exports.onUserWritten = functions.runWith({ serviceAccount: "egyptian-tourism-app@appspot.gserviceaccount.com" }).firestore
    .document("users/{userId}")
    .onWrite(async (change, context) => {
        const userId = context.params.userId;
        const pgClient = getPgClient();

        try {
            await pgClient.connect();

            // Document Deleted
            if (!change.after.exists) {
                await pgClient.query("DELETE FROM users WHERE id = $1", [userId]);
                functions.logger.info(`User ${userId} deleted from Aurora.`);
                return;
            }

            // Document Created or Updated
            const u = change.after.data();
            const createdAt = parseDate(u.createdAt);
            
            await pgClient.query(
                `INSERT INTO users (id, name, email, phone, role, created_at, favorite_product_ids, favorite_artifact_ids, favorite_bazaar_ids) 
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) 
                 ON CONFLICT (id) DO UPDATE SET 
                 name = EXCLUDED.name, email = EXCLUDED.email, phone = EXCLUDED.phone, role = EXCLUDED.role,
                 favorite_product_ids = EXCLUDED.favorite_product_ids, favorite_artifact_ids = EXCLUDED.favorite_artifact_ids, favorite_bazaar_ids = EXCLUDED.favorite_bazaar_ids;`,
                [
                    userId, u.name || "", u.email || "", u.phone || "", u.role || "user", createdAt,
                    JSON.stringify(u.favoriteProductIds || []), JSON.stringify(u.favoriteArtifactIds || []), JSON.stringify(u.favoriteBazaarIds || [])
                ]
            );
            functions.logger.info(`User ${userId} synced to Aurora.`);
        } catch (error) {
            functions.logger.error("Error syncing user:", error);
        } finally {
            await pgClient.end();
        }
    });

// ---------------------------------------------
// 2. Sync Bazaars
// ---------------------------------------------
exports.onBazaarWritten = functions.runWith({ serviceAccount: "egyptian-tourism-app@appspot.gserviceaccount.com" }).firestore
    .document("bazaars/{bazaarId}")
    .onWrite(async (change, context) => {
        const bazaarId = context.params.bazaarId;
        const pgClient = getPgClient();

        try {
            await pgClient.connect();

            // Document Deleted
            if (!change.after.exists) {
                await pgClient.query("DELETE FROM bazaars WHERE id = $1", [bazaarId]);
                functions.logger.info(`Bazaar ${bazaarId} deleted from Aurora.`);
                return;
            }

            // Document Created or Updated
            const b = change.after.data();
            const prev = change.before.exists ? change.before.data() : null;
            const createdAt = parseDate(b.createdAt);
            
            const currentText = `${b.nameAr || ""} - ${b.nameEn || ""}. ${b.descriptionAr || ""}. يقع في ${b.address || ""}.`;
            const prevText = prev ? `${prev.nameAr || ""} - ${prev.nameEn || ""}. ${prev.descriptionAr || ""}. يقع في ${prev.address || ""}.` : "";

            let embeddingStr = null;

            // Only generate new embedding if it's a new document OR text content changed
            if (!prev || currentText !== prevText) {
                const vector = await getEmbedding(currentText);
                embeddingStr = formatVector(vector);
            }

            if (embeddingStr) {
                // Insert or Update with new embedding
                await pgClient.query(
                    `INSERT INTO bazaars (id, name_ar, name_en, description_ar, address, working_hours, phone, latitude, longitude, rating, review_count, is_open, is_approved, embedding, created_at)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15) 
                     ON CONFLICT (id) DO UPDATE SET 
                     name_ar = EXCLUDED.name_ar, name_en = EXCLUDED.name_en, description_ar = EXCLUDED.description_ar, 
                     address = EXCLUDED.address, working_hours = EXCLUDED.working_hours, phone = EXCLUDED.phone, 
                     latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude, rating = EXCLUDED.rating, 
                     review_count = EXCLUDED.review_count, is_open = EXCLUDED.is_open, is_approved = EXCLUDED.is_approved, 
                     embedding = EXCLUDED.embedding;`,
                    [
                        bazaarId, b.nameAr || "", b.nameEn || "", b.descriptionAr || "", b.address || "", b.workingHours || "", b.phone || "",
                        b.latitude || 0.0, b.longitude || 0.0, b.rating || 0.0, b.reviewCount || 0, b.isOpen || false, b.isApproved || false,
                        embeddingStr, createdAt
                    ]
                );
            } else {
                // Update text fields only, preserve existing embedding
                await pgClient.query(
                    `UPDATE bazaars SET 
                     name_ar = $2, name_en = $3, description_ar = $4, address = $5, working_hours = $6, phone = $7, 
                     latitude = $8, longitude = $9, rating = $10, review_count = $11, is_open = $12, is_approved = $13 
                     WHERE id = $1;`,
                    [
                        bazaarId, b.nameAr || "", b.nameEn || "", b.descriptionAr || "", b.address || "", b.workingHours || "", b.phone || "",
                        b.latitude || 0.0, b.longitude || 0.0, b.rating || 0.0, b.reviewCount || 0, b.isOpen || false, b.isApproved || false
                    ]
                );
            }
            functions.logger.info(`Bazaar ${bazaarId} synced to Aurora.`);
        } catch (error) {
            functions.logger.error("Error syncing bazaar:", error);
        } finally {
            await pgClient.end();
        }
    });

// ---------------------------------------------
// 3. Sync Products
// ---------------------------------------------
exports.onProductWritten = functions.runWith({ serviceAccount: "egyptian-tourism-app@appspot.gserviceaccount.com" }).firestore
    .document("products/{productId}")
    .onWrite(async (change, context) => {
        const productId = context.params.productId;
        const pgClient = getPgClient();

        try {
            await pgClient.connect();

            // Document Deleted
            if (!change.after.exists) {
                await pgClient.query("DELETE FROM products WHERE id = $1", [productId]);
                functions.logger.info(`Product ${productId} deleted from Aurora.`);
                return;
            }

            // Document Created or Updated
            const p = change.after.data();
            const prev = change.before.exists ? change.before.data() : null;
            const createdAt = parseDate(p.createdAt);
            
            const currentText = `${p.nameAr || ""} - ${p.nameEn || ""}. ${p.descriptionAr || ""}. السعر: ${p.price || 0}. المادة: ${p.material || ""}. البازار: ${p.bazaarName || ""}`;
            const prevText = prev ? `${prev.nameAr || ""} - ${prev.nameEn || ""}. ${prev.descriptionAr || ""}. السعر: ${prev.price || 0}. المادة: ${prev.material || ""}. البازار: ${prev.bazaarName || ""}` : "";

            let embeddingStr = null;

            if (!prev || currentText !== prevText) {
                const vector = await getEmbedding(currentText);
                embeddingStr = formatVector(vector);
            }

            if (embeddingStr) {
                // Insert or Update with new embedding
                await pgClient.query(
                    `INSERT INTO products (id, name_ar, name_en, description_ar, description_en, price, old_price, rating, review_count, sizes, is_active, is_featured, image_url, category_name, bazaar_name, bazaar_id, material, embedding, created_at)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19) 
                     ON CONFLICT (id) DO UPDATE SET 
                     name_ar = EXCLUDED.name_ar, name_en = EXCLUDED.name_en, description_ar = EXCLUDED.description_ar, 
                     description_en = EXCLUDED.description_en, price = EXCLUDED.price, old_price = EXCLUDED.old_price, 
                     rating = EXCLUDED.rating, review_count = EXCLUDED.review_count, sizes = EXCLUDED.sizes, 
                     is_active = EXCLUDED.is_active, is_featured = EXCLUDED.is_featured, image_url = EXCLUDED.image_url, 
                     category_name = EXCLUDED.category_name, bazaar_name = EXCLUDED.bazaar_name, bazaar_id = EXCLUDED.bazaar_id, 
                     material = EXCLUDED.material, embedding = EXCLUDED.embedding;`,
                    [
                        productId, p.nameAr || "", p.nameEn || "", p.descriptionAr || "", p.descriptionEn || "", p.price || 0, p.oldPrice || 0,
                        p.rating || 0.0, p.reviewCount || 0, p.sizes ? JSON.stringify(p.sizes) : "[]", p.isActive || true, p.isFeatured || false,
                        p.imageUrl || "", p.categoryName || "", p.bazaarName || "", p.bazaarId || "", p.material || "",
                        embeddingStr, createdAt
                    ]
                );
            } else {
                // Update text fields only, preserve existing embedding
                await pgClient.query(
                    `UPDATE products SET 
                     name_ar = $2, name_en = $3, description_ar = $4, description_en = $5, price = $6, old_price = $7, 
                     rating = $8, review_count = $9, sizes = $10, is_active = $11, is_featured = $12, image_url = $13, 
                     category_name = $14, bazaar_name = $15, bazaar_id = $16, material = $17 
                     WHERE id = $1;`,
                    [
                        productId, p.nameAr || "", p.nameEn || "", p.descriptionAr || "", p.descriptionEn || "", p.price || 0, p.oldPrice || 0,
                        p.rating || 0.0, p.reviewCount || 0, p.sizes ? JSON.stringify(p.sizes) : "[]", p.isActive || true, p.isFeatured || false,
                        p.imageUrl || "", p.categoryName || "", p.bazaarName || "", p.bazaarId || "", p.material || ""
                    ]
                );
            }
            
            // Trigger AI Backend to sync image embeddings in the background
            const aiBackendUrl = process.env.AI_BACKEND_URL || "https://b6v2k250la.execute-api.us-east-1.amazonaws.com/prod";
            try {
                await fetch(`${aiBackendUrl}/api/embeddings/sync-images`, { method: "POST" })
                    .catch(err => functions.logger.warn("Failed to trigger image sync:", err));
            } catch(e) {
                // Ignore fetch errors to not crash the main function
                functions.logger.warn("Fetch exception:", e);
            }
            
            functions.logger.info(`Product ${productId} synced to Aurora.`);
        } catch (error) {
            functions.logger.error("Error syncing product:", error);
        } finally {
            await pgClient.end();
        }
    });

// ---------------------------------------------
// 4. Sync Reviews
// ---------------------------------------------
exports.onReviewWritten = functions.runWith({ serviceAccount: "egyptian-tourism-app@appspot.gserviceaccount.com" }).firestore
    .document("reviews/{reviewId}")
    .onWrite(async (change, context) => {
        const reviewId = context.params.reviewId;
        const pgClient = getPgClient();

        try {
            await pgClient.connect();

            // Document Deleted
            if (!change.after.exists) {
                await pgClient.query("DELETE FROM reviews WHERE id = $1", [reviewId]);
                functions.logger.info(`Review ${reviewId} deleted from Aurora.`);
                return;
            }

            // Document Created or Updated
            const r = change.after.data();
            const createdAt = parseDate(r.createdAt);

            await pgClient.query(
                `INSERT INTO reviews (id, bazaar_id, product_id, rating, comment, created_at)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 ON CONFLICT (id) DO UPDATE SET
                 bazaar_id = EXCLUDED.bazaar_id, product_id = EXCLUDED.product_id, rating = EXCLUDED.rating, comment = EXCLUDED.comment;`,
                [reviewId, r.bazaarId || "", r.productId || "", r.rating || 0, r.comment || "", createdAt]
            );
            functions.logger.info(`Review ${reviewId} synced to Aurora.`);
        } catch (error) {
            functions.logger.error("Error syncing review:", error);
        } finally {
            await pgClient.end();
        }
    });

// ---------------------------------------------
// 5. Sync Orders
// ---------------------------------------------
exports.onOrderWritten = functions.runWith({ serviceAccount: "egyptian-tourism-app@appspot.gserviceaccount.com" }).firestore
    .document("orders/{orderId}")
    .onWrite(async (change, context) => {
        const orderId = context.params.orderId;
        const pgClient = getPgClient();
        const crypto = require('crypto');

        try {
            await pgClient.connect();

            // Document Deleted
            if (!change.after.exists) {
                await pgClient.query("DELETE FROM orders WHERE id = $1", [orderId]);
                await pgClient.query("DELETE FROM order_items WHERE order_id = $1", [orderId]);
                functions.logger.info(`Order ${orderId} deleted from Aurora.`);
                return;
            }

            // Document Created or Updated
            const o = change.after.data();
            const createdAt = parseDate(o.createdAt);
            let bazaarId = o.bazaarId || o.bazaar_id || null;
            if (bazaarId === "") bazaarId = null;

            await pgClient.query(
                `INSERT INTO orders (id, user_id, bazaar_id, total_amount, status, created_at)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 ON CONFLICT (id) DO UPDATE SET
                 status = EXCLUDED.status, total_amount = EXCLUDED.total_amount, created_at = EXCLUDED.created_at;`,
                [orderId, o.userId || o.customerId || 'unknown_user', bazaarId, parseFloat(o.totalAmount || o.total || o.subtotal || 0.0), o.paymentStatus || o.status || 'delivered', createdAt]
            );

            // Sync Order Items if any
            const items = o.items || [];
            if (Array.isArray(items)) {
                await pgClient.query("DELETE FROM order_items WHERE order_id = $1", [orderId]);
                for (const item of items) {
                    await pgClient.query(
                        `INSERT INTO order_items (id, order_id, product_id, quantity, price, price_at_purchase) VALUES ($1, $2, $3, $4, $5, $6);`,
                        [crypto.randomBytes(16).toString('hex'), orderId, item.productId || item.product_id || null, item.quantity || 1, parseFloat(item.price || 0.0), parseFloat(item.price || 0.0)]
                    );
                }
            }

            functions.logger.info(`Order ${orderId} synced to Aurora.`);
        } catch (error) {
            functions.logger.error("Error syncing order:", error);
        } finally {
            await pgClient.end();
        }
    });

// ---------------------------------------------
// 6. Sync SubOrders
// ---------------------------------------------
exports.onSubOrderWritten = functions.runWith({ serviceAccount: "egyptian-tourism-app@appspot.gserviceaccount.com" }).firestore
    .document("subOrders/{subOrderId}")
    .onWrite(async (change, context) => {
        const subOrderId = context.params.subOrderId;
        const pgClient = getPgClient();
        const crypto = require('crypto');

        try {
            await pgClient.connect();

            // Document Deleted
            if (!change.after.exists) {
                await pgClient.query("DELETE FROM orders WHERE id = $1", [subOrderId]);
                await pgClient.query("DELETE FROM order_items WHERE order_id = $1", [subOrderId]);
                functions.logger.info(`SubOrder ${subOrderId} deleted from Aurora.`);
                return;
            }

            // Document Created or Updated
            const o = change.after.data();
            const createdAt = parseDate(o.createdAt || o.deliveredAt);
            let bazaarId = o.bazaarId || o.bazaar_id || null;
            if (bazaarId === "") bazaarId = null;

            await pgClient.query(
                `INSERT INTO orders (id, user_id, bazaar_id, total_amount, status, created_at)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 ON CONFLICT (id) DO UPDATE SET
                 status = EXCLUDED.status, total_amount = EXCLUDED.total_amount, created_at = EXCLUDED.created_at;`,
                [subOrderId, o.customerId || o.userId || 'unknown_user', bazaarId, parseFloat(o.subtotal || o.totalAmount || o.total || 0.0), o.status || 'pending', createdAt]
            );

            // Sync Order Items (from SubOrder items)
            const items = o.items || [];
            if (Array.isArray(items)) {
                await pgClient.query("DELETE FROM order_items WHERE order_id = $1", [subOrderId]);
                for (const item of items) {
                    await pgClient.query(
                        `INSERT INTO order_items (id, order_id, product_id, quantity, price, price_at_purchase) VALUES ($1, $2, $3, $4, $5, $6);`,
                        [crypto.randomBytes(16).toString('hex'), subOrderId, item.productId || item.product_id || null, item.quantity || 1, parseFloat(item.price || 0.0), parseFloat(item.price || 0.0)]
                    );
                }
            }
            functions.logger.info(`SubOrder ${subOrderId} synced to Aurora.`);
        } catch (error) {
            functions.logger.error("Error syncing subOrder:", error);
        } finally {
            await pgClient.end();
        }
    });

// ---------------------------------------------
// 7. Sync Messages
// ---------------------------------------------
exports.onMessageWritten = functions.runWith({ serviceAccount: "egyptian-tourism-app@appspot.gserviceaccount.com" }).firestore
    .document("messages/{messageId}")
    .onWrite(async (change, context) => {
        const messageId = context.params.messageId;
        const pgClient = getPgClient();

        try {
            await pgClient.connect();

            // Document Deleted
            if (!change.after.exists) {
                await pgClient.query("DELETE FROM messages WHERE id = $1", [messageId]);
                functions.logger.info(`Message ${messageId} deleted from Aurora.`);
                return;
            }

            // Document Created or Updated
            const m = change.after.data();
            const createdAt = parseDate(m.createdAt || m.lastMessageAt);
            let bazaarId = m.bazaarId || m.bazaar_id || null;
            if (bazaarId === "") bazaarId = null;

            let customerId = m.customerId || m.customer_id || null;
            if (customerId === "") customerId = null;

            await pgClient.query(
                `INSERT INTO messages (id, bazaar_id, customer_id, content, created_at)
                 VALUES ($1, $2, $3, $4, $5)
                 ON CONFLICT (id) DO UPDATE SET
                 content = EXCLUDED.content, created_at = EXCLUDED.created_at;`,
                [messageId, bazaarId, customerId, m.content || m.initialMessage || "", createdAt]
            );
            
            functions.logger.info(`Message ${messageId} synced to Aurora.`);
        } catch (error) {
            functions.logger.error("Error syncing message:", error);
        } finally {
            await pgClient.end();
        }
    });
