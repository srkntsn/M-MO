import {appendFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';

export function normalizeDeploymentToken(value) {
  const unquote = (s) => {
    const pairs = {'"':'"', "'":"'", '“':'”', '‘':'’'};
    return s.length > 1 && pairs[s[0]] === s.at(-1) ? s.slice(1,-1).trim() : s;
  };
  const token = unquote(unquote(String(value || '').trim()).replace(/^Bearer[ \t]+/i,'').trim());
  if (!/^[A-Za-z0-9._~-]{20,4096}$/.test(token)) throw new Error('API token contains extra text, internal whitespace, or an invalid value. Copy only the generated token into CLOUDFLARE_API_TOKEN.');
  if (/^[a-fA-F0-9]{32}$/.test(token)) throw new Error('CLOUDFLARE_API_TOKEN contains a 32-character hexadecimal identifier, not a Cloudflare API token. Keep the account ID only in CLOUDFLARE_ACCOUNT_ID. No secret value was printed.');
  return token;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const raw = process.env.CF_TOKEN || '';
    const token = normalizeDeploymentToken(raw);
    const account = (process.env.CF_ACCOUNT || '').trim();
    if (!/^[a-fA-F0-9]{32}$/.test(account)) throw new Error('Cloudflare account ID must contain 32 hexadecimal characters.');
    if (token === account) throw new Error('CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID contain the same value. An account ID cannot authenticate deployment. No secret value was printed.');
    if (!process.env.GITHUB_ENV) throw new Error('GitHub Actions environment file is missing.');
    console.log('::add-mask::' + token);
    appendFileSync(process.env.GITHUB_ENV, 'MIMO_DEPLOY_TOKEN=' + token + '\nMIMO_DEPLOY_ACCOUNT=' + account + '\n');
    console.log(raw === token ? 'Deployment credential format validated.' : 'Removed surrounding whitespace, quotes, or Bearer prefix.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
