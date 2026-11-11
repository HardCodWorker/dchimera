import Foundation

/// A small shop database (SQLite) so the app has something to show right away.
enum DemoDatabase {
    static func create(at url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let driver = try SQLiteDriver(path: url.path, readOnly: false, create: true)
        _ = try await driver.execute(script, rowLimit: nil)
        await driver.close()
    }

    static let script = """
    PRAGMA journal_mode = WAL;
    BEGIN;
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT UNIQUE,
      country TEXT NOT NULL,
      city TEXT,
      vip INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    );
    CREATE TABLE products (
      id INTEGER PRIMARY KEY,
      title TEXT NOT NULL,
      category TEXT NOT NULL,
      price REAL NOT NULL,
      stock INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE orders (
      id INTEGER PRIMARY KEY,
      customer_id INTEGER NOT NULL REFERENCES customers(id),
      status TEXT NOT NULL,
      total REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    );
    CREATE TABLE order_items (
      id INTEGER PRIMARY KEY,
      order_id INTEGER NOT NULL REFERENCES orders(id),
      product_id INTEGER NOT NULL REFERENCES products(id),
      qty INTEGER NOT NULL,
      price REAL NOT NULL
    );
    CREATE TABLE events (
      id INTEGER PRIMARY KEY,
      kind TEXT NOT NULL,
      payload TEXT,
      at TEXT NOT NULL
    );
    CREATE INDEX idx_orders_customer ON orders(customer_id);
    CREATE INDEX idx_orders_status ON orders(status, created_at);
    CREATE INDEX idx_items_order ON order_items(order_id);
    CREATE UNIQUE INDEX idx_products_title ON products(title);

    WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 240)
    INSERT INTO customers (id, name, email, country, city, vip, created_at)
    SELECT n,
      json_extract('["Anna","Boris","Chen","Dana","Elif","Farid","Greta","Hiro","Ivan","Jules","Kira","Liam","Maya","Nikos","Olga","Pavel","Quinn","Rosa","Sven","Tara"]', '$[' || ((n * 7) % 20) || ']')
        || ' ' ||
      json_extract('["Smith","Ivanova","Garcia","Kim","Novak","Rossi","Müller","Silva","Tanaka","Petrov","Cohen","Dubois"]', '$[' || ((n * 5) % 12) || ']'),
      'user' || n || '@example.com',
      json_extract('["Germany","Spain","Japan","Brazil","Canada","Poland","Italy","Georgia"]', '$[' || ((n * 3) % 8) || ']'),
      json_extract('["Berlin","Madrid","Tokyo","Rio","Toronto","Warsaw","Milan","Tbilisi"]', '$[' || ((n * 3) % 8) || ']'),
      CASE WHEN n % 9 = 0 THEN 1 ELSE 0 END,
      datetime('2025-01-01', '+' || ((n * 37) % 600) || ' days', '+' || ((n * 1307) % 86400) || ' seconds')
    FROM seq;

    WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 40)
    INSERT INTO products (id, title, category, price, stock)
    SELECT n,
      json_extract('["Aurora","Nimbus","Quartz","Ember","Drift","Pulse","Orbit","Echo","Flux","Prism"]', '$[' || (n % 10) || ']')
        || ' ' ||
      json_extract('["Lamp","Chair","Mug","Backpack"]', '$[' || ((n / 10) % 4) || ']'),
      json_extract('["Lighting","Furniture","Kitchen","Travel"]', '$[' || ((n / 10) % 4) || ']'),
      round(9.99 + ((n * 7919) % 25000) / 100.0, 2),
      (n * 37) % 120
    FROM seq;

    WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 1800)
    INSERT INTO orders (id, customer_id, status, created_at)
    SELECT n,
      ((n * 31) % 240) + 1,
      json_extract('["delivered","delivered","delivered","shipped","paid","paid","pending","cancelled","refunded","delivered"]', '$[' || (n % 10) || ']'),
      datetime('2025-03-01', '+' || ((n * 11) % 610) || ' days', '+' || ((n * 7717) % 86400) || ' seconds')
    FROM seq;

    WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 4600)
    INSERT INTO order_items (id, order_id, product_id, qty, price)
    SELECT n, (n % 1800) + 1, ((n * 17) % 40) + 1, (n % 4) + 1,
      (SELECT price FROM products WHERE id = ((n * 17) % 40) + 1)
    FROM seq;

    UPDATE orders SET total = round((SELECT coalesce(sum(qty * price), 0) FROM order_items WHERE order_id = orders.id), 2);

    WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 320)
    INSERT INTO events (id, kind, payload, at)
    SELECT n,
      json_extract('["login","search","add_to_cart","checkout","logout"]', '$[' || (n % 5) || ']'),
      json_object('customer', ((n * 13) % 240) + 1, 'device', CASE n % 3 WHEN 0 THEN 'ios' WHEN 1 THEN 'web' ELSE 'android' END, 'ms', (n * 97) % 900),
      datetime('2026-10-01', '+' || ((n * 3) % 40) || ' days', '+' || ((n * 3001) % 86400) || ' seconds')
    FROM seq;

    UPDATE customers SET city = NULL WHERE id % 23 = 0;

    CREATE VIEW revenue_by_country AS
    SELECT c.country, count(DISTINCT o.id) AS orders, round(sum(o.total), 2) AS revenue
    FROM orders o JOIN customers c ON c.id = o.customer_id
    WHERE o.status IN ('paid', 'shipped', 'delivered')
    GROUP BY c.country
    ORDER BY revenue DESC;
    COMMIT;
    """
}
