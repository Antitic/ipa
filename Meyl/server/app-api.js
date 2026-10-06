/* ============================================================================
   API JSON pour l'app iOS « Meyl » (/app/v1/…).
   Pas de session ni de cookie : chaque requête porte les identifiants du
   compte mail en HTTP Basic (HTTPS de bout en bout via le tunnel Cloudflare).
   Les identifiants déjà vérifiés restent en mémoire 10 min (empreinte SHA-256),
   ce qui évite de rouvrir une connexion IMAP à chaque appel. Même limite
   anti force brute que la page de connexion du webmail.
   ============================================================================ */
const crypto = require('crypto');
const nodemailer = require('nodemailer');
const MailComposer = require('nodemailer/lib/mail-composer');

module.exports = function mountAppApi(app, d) {
  const {
    MAILBOXES, pickBox, withImap, statusAll, listBox, toRow, FETCH_Q, SEARCH_CAP,
    getMessage, shapeMessage, buildMailDocument, notFoundDoc, MAIL_CSP, moveMessage,
    openSession, loginBlocked, noteFail, fails, upload, parseAddrs, EMAIL_RE,
    sentToday, sendCap, SUBMIT_HOST, SUBMIT_PORT,
  } = d;

  const VERIFIED_MS = 10 * 60 * 1000;
  const verified = new Map(); // user -> { h, at }
  const hash = (u, p) => crypto.createHash('sha256').update(u + '\u0000' + p).digest('hex');

  function parseBasic(req) {
    const h = req.get('authorization') || '';
    const m = h.match(/^Basic\s+(.+)$/i);
    if (!m) return null;
    let raw;
    try { raw = Buffer.from(m[1], 'base64').toString('utf8'); } catch (e) { return null; }
    const i = raw.indexOf(':');
    if (i < 1) return null;
    return { user: raw.slice(0, i).trim().toLowerCase(), pass: raw.slice(i + 1) };
  }

  async function auth(req, res, next) {
    res.set('Cache-Control', 'no-store');
    const creds = parseBasic(req);
    if (!creds || !creds.pass) return res.status(401).json({ error: 'Identifiants manquants.' });
    const v = verified.get(creds.user);
    if (v && v.h === hash(creds.user, creds.pass) && Date.now() - v.at < VERIFIED_MS) {
      req.creds = creds;
      return next();
    }
    const wait = loginBlocked(req.ip);
    if (wait) return res.status(429).json({ error: `Trop de tentatives. Réessaie dans ${wait} min.` });
    try {
      await openSession(creds.user, creds.pass);
      fails.delete(req.ip);
      verified.set(creds.user, { h: hash(creds.user, creds.pass), at: Date.now() });
      req.creds = creds;
      return next();
    } catch (e) {
      if (e && e.authenticationFailed) {
        noteFail(req.ip);
        verified.delete(creds.user);
        return res.status(401).json({ error: 'Adresse ou mot de passe incorrect.' });
      }
      return res.status(502).json({ error: 'Le serveur mail ne répond pas.' });
    }
  }

  setInterval(function () {
    const limit = Date.now() - VERIFIED_MS;
    for (const [u, v] of verified) if (v.at < limit) verified.delete(u);
  }, 5 * 60 * 1000).unref();

  const fail502 = (res, e) => res.status(502).json({ error: (e && e.message) || 'Erreur du serveur mail.' });
  const iso = (dt) => (dt ? new Date(dt).toISOString() : null);
  const rowOut = (r) => Object.assign({}, r, { date: iso(r.date) });

  /* Qui suis-je + dossiers et compteurs. Sert aussi de test de connexion. */
  app.get('/app/v1/me', auth, async (req, res) => {
    try {
      const counts = await withImap(req.creds, (c) => statusAll(c));
      res.json({
        user: req.creds.user,
        boxes: MAILBOXES.map((m) => Object.assign({ path: m.path, label: m.label, icon: m.icon }, counts[m.path] || {})),
      });
    } catch (e) { fail502(res, e); }
  });

  /* Liste d'un dossier (60 par page, ?before=<uid> pour la suite). */
  app.get('/app/v1/list', auth, async (req, res) => {
    const box = pickBox(req.query.box);
    const before = Number(req.query.before) || 0;
    try {
      const r = await withImap(req.creds, (c) => listBox(c, box, before || undefined));
      res.json({ box, rows: r.rows.map(rowOut), more: r.more });
    } catch (e) { fail502(res, e); }
  });

  /* Compteurs + nouveaux messages de la réception depuis un UID. */
  app.get('/app/v1/poll', auth, async (req, res) => {
    const after = Number(req.query.after) || 0;
    try {
      const out = await withImap(req.creds, async (client) => {
        const counts = await statusAll(client);
        const rows = [];
        if (after && counts.INBOX.uidNext && counts.INBOX.uidNext - 1 > after) {
          const lock = await client.getMailboxLock('INBOX', { readOnly: true });
          try {
            for await (const msg of client.fetch((after + 1) + ':*', FETCH_Q, { uid: true })) {
              if (msg.uid > after) rows.push(toRow(msg, 'INBOX'));
            }
          } finally { lock.release(); }
          rows.sort((a, b) => b.uid - a.uid);
        }
        return { counts, rows };
      });
      res.json({ counts: out.counts, rows: out.rows.map(rowOut) });
    } catch (e) { fail502(res, e); }
  });

  /* Recherche dans tous les dossiers (objet, expéditeur, destinataire, corps). */
  app.get('/app/v1/search', auth, async (req, res) => {
    const q = String(req.query.q || '').trim().slice(0, 200);
    if (q.length < 2) return res.json({ rows: [] });
    try {
      const results = await withImap(req.creds, async (client) => {
        const out = [];
        for (const m of MAILBOXES) {
          let lock;
          try {
            lock = await client.getMailboxLock(m.path, { readOnly: true });
            const uids = await client.search({ or: [{ subject: q }, { from: q }, { to: q }, { body: q }] }, { uid: true }).catch(() => []);
            if (uids && uids.length) {
              for await (const msg of client.fetch(uids.slice(-SEARCH_CAP), FETCH_Q, { uid: true })) out.push(toRow(msg, m.path));
            }
          } catch (e) { /* dossier illisible */ } finally { if (lock) lock.release(); }
        }
        out.sort((a, b) => new Date(b.date || 0) - new Date(a.date || 0));
        return out.slice(0, SEARCH_CAP);
      });
      res.json({ rows: results.map(rowOut) });
    } catch (e) { fail502(res, e); }
  });

  /* Un message (le marque comme lu). */
  app.get('/app/v1/message/:box/:uid', auth, async (req, res) => {
    const box = pickBox(req.params.box);
    const uid = Number(req.params.uid);
    try {
      const mail = await getMessage(req.creds, box, uid, true);
      const m = shapeMessage(mail, box, uid, req.creds.user);
      delete m.user;
      m.date = iso(m.date);
      m.attachments = m.attachments.map((a) => ({ index: a.index, name: a.name, size: a.size, contentType: a.contentType || 'application/octet-stream' }));
      res.json(m);
    } catch (e) {
      res.status(404).json({ error: 'Ce message n\'existe plus.' });
    }
  });

  /* Corps HTML nettoyé (mêmes protections que le webmail ; ?img=1 pour les images distantes). */
  app.get('/app/v1/message/:box/:uid/body', auth, async (req, res) => {
    const box = pickBox(req.params.box);
    const uid = Number(req.params.uid);
    const allowRemote = req.query.img === '1';
    res.set('Content-Security-Policy', MAIL_CSP(allowRemote));
    try {
      const mail = await getMessage(req.creds, box, uid, false);
      res.type('html').send(buildMailDocument(mail, allowRemote));
    } catch (e) {
      res.status(404).type('html').send(notFoundDoc());
    }
  });

  /* Pièce jointe brute. */
  app.get('/app/v1/attachment/:box/:uid/:idx', auth, async (req, res) => {
    const box = pickBox(req.params.box);
    const uid = Number(req.params.uid);
    const idx = Number(req.params.idx);
    try {
      const mail = await getMessage(req.creds, box, uid, false);
      const att = (mail.attachments || [])[idx];
      if (!att) return res.status(404).json({ error: 'Pièce jointe introuvable.' });
      res.set('Content-Type', att.contentType || 'application/octet-stream');
      res.attachment(att.filename || 'piece-jointe');
      res.send(att.content);
    } catch (e) { fail502(res, e); }
  });

  /* Déplacer (to = INBOX | Archive | Trash | delete depuis la corbeille). */
  app.post('/app/v1/move', auth, async (req, res) => {
    const box = pickBox(req.body.box);
    const uid = Number(req.body.uid);
    const to = req.body.to === 'delete' ? 'delete' : pickBox(req.body.to);
    if (!uid || to === box) return res.status(400).json({ error: 'Déplacement invalide.' });
    if (to === 'delete' && box !== 'Trash') return res.status(400).json({ error: 'Suppression définitive : uniquement depuis la corbeille.' });
    try {
      const r = await moveMessage(req.creds, box, uid, to);
      res.json({ ok: true, uid: r.uid, box: to });
    } catch (e) { fail502(res, e); }
  });

  /* Lu / non lu. */
  app.post('/app/v1/flag', auth, async (req, res) => {
    const box = pickBox(req.body.box);
    const uid = Number(req.body.uid);
    const seen = req.body.seen === true || req.body.seen === '1' || req.body.seen === 'true';
    try {
      await withImap(req.creds, async (client) => {
        const lock = await client.getMailboxLock(box);
        try {
          if (seen) await client.messageFlagsAdd(String(uid), ['\\Seen'], { uid: true });
          else await client.messageFlagsRemove(String(uid), ['\\Seen'], { uid: true });
        } finally { lock.release(); }
      });
      res.json({ ok: true });
    } catch (e) { fail502(res, e); }
  });

  /* Envoi (multipart : to, cc, bcc, subject, body, inReplyTo, references, files[]). */
  app.post('/app/v1/send', auth, upload.array('files'), async (req, res) => {
    const { user, pass } = req.creds;
    const { subject, body, inReplyTo, references } = req.body;
    const to = parseAddrs(req.body.to);
    const cc = parseAddrs(req.body.cc);
    const bcc = parseAddrs(req.body.bcc);
    const all = Array.from(new Set(to.concat(cc, bcc)));
    if (!to.length) return res.status(400).json({ error: 'Ajoute au moins un destinataire.' });
    const bad = all.find((a) => !EMAIL_RE.test(a));
    if (bad) return res.status(400).json({ error: 'Adresse invalide : ' + bad });
    if (all.length > 50) return res.status(400).json({ error: 'Trop de destinataires (50 max).' });
    const rec = sentToday(user);
    if (rec.n >= sendCap(user)) return res.status(429).json({ error: 'Limite d\'envoi du jour atteinte. Réessaie demain.' });

    const attachments = (req.files || []).map((f) => ({
      filename: Buffer.from(f.originalname, 'latin1').toString('utf8'),
      content: f.buffer,
      contentType: f.mimetype,
    }));
    let raw;
    try {
      raw = await new MailComposer({
        from: user,
        to: to.join(', '),
        cc: cc.length ? cc.join(', ') : undefined,
        bcc: bcc.length ? bcc.join(', ') : undefined,
        subject: subject || '(sans objet)',
        text: body || '',
        date: new Date(),
        inReplyTo: inReplyTo || undefined,
        references: references || undefined,
        attachments,
      }).compile().build();
    } catch (e) {
      return res.status(400).json({ error: 'Message impossible à composer : ' + e.message });
    }
    const transport = nodemailer.createTransport({
      host: SUBMIT_HOST, port: SUBMIT_PORT, secure: false, ignoreTLS: true, auth: { user, pass },
    });
    let delivered = true;
    try {
      await transport.sendMail({ envelope: { from: user, to: all }, raw });
      rec.n++;
    } catch (e) {
      delivered = false;
    } finally {
      transport.close();
    }
    withImap(req.creds, (client) => client.append('Sent', raw, ['\\Seen']), { retry: false }).catch(() => {});
    res.json({ ok: true, delivered });
  });

  app.use('/app/v1', (req, res) => res.status(404).json({ error: 'Route inconnue.' }));
};
