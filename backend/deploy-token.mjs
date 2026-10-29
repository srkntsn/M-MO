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
    const account = (process.env.CF_ACCOUNT || '').trim();
    if (raw.trim() === account && account) throw new Error('DIAGNOSIS: CLOUDFLARE_API_TOKEN contains exactly the CLOUDFLARE_ACCOUNT_ID value. Replace only the API_TOKEN secret with the generated token value, not the account ID.');
    const token = normalizeDeploymentToken(raw);
    if (!/^[a-fA-F0-9]{32}$/.test(account)) throw new Error('Cloudflare account ID must contain 32 hexadecimal characters.');
    if (token === account) throw new Error('CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID contain the same value. An account ID cannot authenticate deployment. No secret value was printed.');
    const verifyPath = token.startsWith('cfat_') ? '/accounts/' + account + '/tokens/verify' : '/user/tokens/verify';
    const verified = await fetch('https://api.cloudflare.com/client/v4' + verifyPath, {
      headers: {Authorization: 'Bearer ' + token},
      signal: AbortSignal.timeout(10000)
    });
    const verification = await verified.json();
    if (!verified.ok || !verification.success || verification.result?.status !== 'active') {
      const codes = (verification.errors || []).map(x => Number(x.code)).filter(Number.isFinite).join(',');
      throw new Error('TOKEN_VERIFICATION_FAILED: Cloudflare rejected the saved token; status=' + verified.status + ', codes=' + codes + '. No credentials were printed.');
    }
    console.log('TOKEN_VERIFIED_ACTIVE: Saved token is active for its issuing account.');
    if (!process.env.GITHUB_ENV) throw new Error('GitHub Actions environment file is missing.');
    console.log('::add-mask::' + token);
    appendFileSync(process.env.GITHUB_ENV, 'MIMO_DEPLOY_TOKEN=' + token + '\nMIMO_DEPLOY_ACCOUNT=' + account + '\n');
    console.log(raw === token ? 'Deployment credential format validated.' : 'Removed surrounding whitespace, quotes, or Bearer prefix.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
