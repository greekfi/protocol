# Dependency Vulnerabilities Report

**Scan Date**: 2025-12-24
**Total Vulnerabilities**: 42 (1 Critical, 17 High, 16 Moderate, 8 Low)

---

## 🔴 CRITICAL Vulnerabilities (1)

### 1. Next.js - Multiple RCE and Security Issues
**Package**: `next` (versions 15.0.0-canary.0 - 15.4.6 || 16.0.0-beta.0 - 16.0.8)
**Severity**: CRITICAL

**Vulnerabilities**:
- **RCE via React Flight Protocol** (GHSA-9qr9-h5gf-34mp) - Remote code execution
- **Server Actions Source Code Exposure** (GHSA-w37m-7fhw-fmv9) - Leak sensitive code
- **SSRF via Middleware Redirect** (GHSA-4342-x723-ch2f) - Server-side request forgery
- **Cache Key Confusion for Image API** (GHSA-g5qg-72qw-gw5v) - Cache poisoning
- **Content Injection for Image Optimization** (GHSA-xv57-4mr9-wg8v) - XSS/injection
- **DoS with Server Components** (GHSA-mwv6-3258-q52c) - Denial of service

**Fix**:
```bash
npm audit fix  # Updates to patched Next.js version
```

---

## 🟠 HIGH Severity Vulnerabilities (17)

### 2. OpenZeppelin Contracts - Multiple Issues
**Package**: `@openzeppelin/contracts` (versions <= 4.9.5)
**Severity**: HIGH

**Vulnerabilities** (12 total):
- **ECDSA Signature Malleability** (GHSA-4h98-2769-gh6h) - Signature attacks
- **ERC165Checker Unbounded Gas** (GHSA-7grf-83vw-6f5x) - DoS via gas exhaustion
- **SignatureChecker EIP-1271 Revert** (GHSA-4g63-c64m-25w9) - Unexpected reverts
- **MerkleProof Multiproof Bypass** (GHSA-wprv-93r4-jj2p) - Proof forgery
- **TransparentProxy Selector Clashing** (GHSA-mx2q-35m2-x2rh) - Delegation bypass
- **Governor Proposal Frontrunning** (GHSA-5h3x-9wvq-w4m2) - Governance manipulation
- **Base64 Dirty Memory Read** (GHSA-9vx6-7xxf-x967) - Memory corruption
- **GovernorVotesQuorumFraction Issues** (GHSA-xrc4-737v-9q75) - Governance bypass
- **ERC165Checker False Reverts** (GHSA-qh9x-gcfh-pcrw) - Logic errors
- **Improper Escaping of Output** (GHSA-g4vp-m682-qqmp) - XSS potential
- **Arbitrum L2 EOA Call Issues** (GHSA-9j3m-g383-29qr) - Cross-chain bugs
- **GovernorCompatibilityBravo Calldata Trim** (GHSA-93hq-5wgc-jc82) - Data loss

**Current Version in Project**: Likely 4.x (vulnerable)
**Fix**:
```bash
npm audit fix --force  # Breaking change to OZ Contracts v5.x
```

**⚠️ IMPORTANT NOTE**:
Your smart contracts import OpenZeppelin v5.3.0 (seen in Solidity imports), but the package.json might have vulnerable transitive dependencies from Uniswap packages. Check if this affects your actual contracts.

**Impact on Your Protocol**:
- Your contracts use: `Ownable`, `ReentrancyGuard`, `ERC20`, `SafeERC20`, `Clones`, `Initializable`
- Most vulnerabilities are in modules you DON'T use (Governor, MerkleProof, SignatureChecker)
- **Likely LOW actual risk** for your specific contracts, but should still update

---

### 3. glob - Command Injection
**Package**: `glob` (versions 10.2.0 - 10.4.5)
**Severity**: HIGH

**Vulnerability**:
- **Command Injection via CLI** (GHSA-5j98-mcp5-4vw2)
- The glob CLI `-c/--cmd` flag executes matches with `shell:true`, allowing command injection

**Fix**:
```bash
npm audit fix  # Updates to glob 10.4.6+
```

---

### 4. path-to-regexp - ReDoS (Regular Expression DoS)
**Package**: `path-to-regexp` (versions 4.0.0 - 6.2.2)
**Severity**: HIGH

**Vulnerability**:
- **Backtracking Regex DoS** (GHSA-9wv6-86v2-598j)
- Can cause CPU exhaustion via crafted route patterns

**Affected Dependencies**: Vercel deployment tools
**Fix**:
```bash
npm audit fix --force  # May require Vercel update
```

---

### 5. semver - ReDoS
**Package**: `semver` (versions 7.0.0 - 7.5.1)
**Severity**: HIGH

**Vulnerability**:
- **Regular Expression DoS** (GHSA-c2qf-rxjj-qqgw)

**Fix**:
```bash
npm audit fix --force
```

---

### 6. parse-duration - ReDoS + OOM
**Package**: `parse-duration` (< 2.1.3)
**Severity**: HIGH

**Vulnerability**:
- **Regex DoS + Memory Exhaustion** (GHSA-hcrg-fc28-fcg5)
- Can cause event loop delay and out-of-memory crashes

**Affected**: `kubo-rpc-client` (IPFS client)
**Fix**:
```bash
npm audit fix --force
```

---

## 🟡 MODERATE Severity Vulnerabilities (16)

### 7. esbuild - Development Server SSRF
**Package**: `esbuild` (<= 0.24.2)
**Severity**: MODERATE

**Vulnerability**:
- **Dev Server Request Forwarding** (GHSA-67mh-4wv8-2f99)
- During development, any website can send requests to dev server and read responses
- **Only affects development mode**, not production

**Fix**:
```bash
npm audit fix --force
```

---

### 8. MetaMask SDK - Malicious debug Dependency
**Package**: `@metamask/sdk` (0.16.0 - 0.33.0)
**Severity**: MODERATE

**Vulnerability**:
- **Malicious debug@4.4.2 dependency** (GHSA-qj3p-xc97-xw74)
- Specific version of debug package was compromised

**Affected**: Wagmi connectors for MetaMask
**Fix**:
```bash
npm audit fix --force  # Updates burner-connector
```

---

### 9. js-yaml - Prototype Pollution
**Package**: `js-yaml` (4.0.0 - 4.1.0)
**Severity**: MODERATE

**Vulnerability**:
- **Prototype Pollution via Merge** (GHSA-mh29-5h37-fv8m)
- The `<<` merge operator can pollute Object.prototype

**Fix**:
```bash
npm audit fix
```

---

### 10. debug - ReDoS
**Package**: `debug` (4.0.0 - 4.3.0)
**Severity**: MODERATE (but used widely)

**Vulnerability**:
- **Regular Expression DoS** (GHSA-gxpj-cx7g-858c)

**Affected**: Vercel tooling (transitive dependency)
**Fix**:
```bash
npm audit fix --force
```

---

## 🟢 LOW Severity Vulnerabilities (8)

### 11. @eslint/plugin-kit - ReDoS
**Package**: `@eslint/plugin-kit` (< 0.3.4)
**Severity**: LOW

**Vulnerability**:
- **ReDoS in ConfigCommentParser** (GHSA-xffm-g5w8-qvg7)
- Only affects linting/development, not runtime

**Fix**:
```bash
npm audit fix --force  # Updates ESLint
```

---

### 12. @inquirer/editor - External Editor Issues
**Package**: `@inquirer/editor` (<= 4.2.15)
**Severity**: LOW

**Affected**: `bgipfs` package (development tooling)
**No fix available** currently

---

## Summary by Risk Category

### Immediate Action Required (CRITICAL + HIGH affecting production):
1. ✅ **Update Next.js** - RCE vulnerabilities, actively exploitable
2. ⚠️ **Review OpenZeppelin Contracts** - Check if vulnerabilities affect your specific usage
3. ✅ **Update glob** - If using glob CLI features
4. ✅ **Update path-to-regexp** - Affects Vercel routing

### Medium Priority (Development/Edge Cases):
5. **Update esbuild** - Only affects dev mode
6. **Update MetaMask SDK** - Specific malicious dependency
7. **Update js-yaml, debug, semver** - Transitive dependencies

### Low Priority (Linting/Tooling):
8. **Update ESLint plugins** - Development only
9. **Monitor inquirer/editor** - No fix available yet

---

## Recommended Action Plan

### Step 1: Fix Critical Next.js Issues (IMMEDIATE)
```bash
npm audit fix
```
This will update Next.js to a patched version and fix most issues.

### Step 2: Check OpenZeppelin Contracts (REVIEW)
```bash
# Check what version is actually used in your Solidity contracts
grep "@openzeppelin/contracts" packages/foundry/package.json

# If it's a transitive dependency from Uniswap, it likely doesn't affect your contracts
# Your Solidity contracts import from v5.3.0 which is secure
```

### Step 3: Force-Fix Remaining Issues (OPTIONAL)
```bash
npm audit fix --force
```
⚠️ **Warning**: This may introduce breaking changes. Test thoroughly.

### Step 4: Manual Review for No-Fix Items
Some vulnerabilities have no automatic fix. Review if these packages are actually used:
- `@inquirer/editor` (likely unused in production)
- Various Uniswap SDK packages (may be dev dependencies)

---

## Dependency Hygiene Recommendations

1. **Separate dev and prod dependencies**:
   - Move Vercel, ESLint, testing tools to `devDependencies`
   - Reduces attack surface in production

2. **Update regularly**:
   ```bash
   npm outdated
   npm update
   ```

3. **Use npm overrides** for stubborn transitive dependencies:
   ```json
   "overrides": {
     "@openzeppelin/contracts": "^5.3.0",
     "debug": "^4.3.7",
     "semver": "^7.6.3"
   }
   ```

4. **Consider using Snyk or Dependabot**:
   - GitHub already flagged these (seen in your push output)
   - Enable automated PR creation for security updates

---

## Risk Assessment for Your Protocol

**Smart Contract Dependencies**: ✅ **LOW RISK**
- Your Solidity contracts use OpenZeppelin v5.3.0 (secure)
- Vulnerabilities are in npm packages, not Solidity dependencies

**Frontend/Deployment**: ⚠️ **MODERATE RISK**
- Next.js RCE vulnerabilities are serious for production
- Most other issues affect dev mode or edge cases

**Overall**: Fix Next.js immediately, review others at your convenience.
