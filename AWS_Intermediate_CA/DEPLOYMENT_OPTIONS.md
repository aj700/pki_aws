# AWS PKI Deployment Options Analysis

This document analyzes deployment options for the ACME Corporation PKI infrastructure in AWS, weighing cost, security, compliance, and deployment speed.

## Decision Vectors

| Vector | Weight | Description |
|--------|--------|-------------|
| **Cost** | High | Monthly operational expense |
| **Deployment Speed** | High | Time to production-ready state |
| **Security** | Medium | Key protection and cryptographic assurance |
| **Compliance** | Variable | FIPS 140-2 certification level |
| **Operational Complexity** | Medium | Ongoing maintenance burden |
| **Scalability** | Low | Certificate issuance capacity |

---

## Options Evaluated

### Option A: AWS ACM Private CA (Full)

**Architecture:** Managed Root CA + Managed Intermediate CA

| Pros | Cons |
|------|------|
| ✅ Zero infrastructure management | ❌ **~$800/month** (~$9,600/year) |
| ✅ FIPS 140-2 Level 3 HSM-backed | ❌ Limited certificate customization |
| ✅ Built-in OCSP and CRL | ❌ Vendor lock-in |
| ✅ 10-minute deployment | ❌ Per-certificate costs at scale |
| ✅ Native AWS service integration | |

**Best for:** Enterprises with compliance requirements and budget tolerance.

---

### Option B: EC2 + CloudHSM

**Architecture:** Self-managed CA on EC2, keys in dedicated HSM cluster

| Pros | Cons |
|------|------|
| ✅ FIPS 140-2 Level 3 compliance | ❌ **~$2,400+/month** (2 HSMs for HA) |
| ✅ Full algorithm control (P-384 ✓) | ❌ 1-2 day deployment time |
| ✅ No per-certificate costs | ❌ HSM cluster management overhead |
| ✅ Portable (standard PKCS#11) | ❌ Complex disaster recovery |

**Best for:** High-security environments requiring dedicated HSMs with full control.

---

### Option C: EC2 + AWS KMS

**Architecture:** Self-managed CA on EC2, asymmetric keys in KMS

| Pros | Cons |
|------|------|
| ✅ Low cost (~$5-20/month) | ❌ FIPS 140-2 Level 2 only |
| ✅ KMS manages key lifecycle | ❌ KMS doesn't export private keys |
| ✅ P-384 supported for signing | ❌ Complex OpenSSL-KMS integration |
| ✅ ~2 hour deployment | ❌ API rate limits for high volume |

**Best for:** Cost-conscious deployments needing some HSM protection without full FIPS L3.

---

### Option D: HashiCorp Vault PKI

**Architecture:** Vault OSS or Enterprise on EC2 with PKI secrets engine

| Pros | Cons |
|------|------|
| ✅ Built-in PKI engine with REST API | ❌ Learning curve |
| ✅ Dynamic secrets, auto-rotation | ❌ Another system to manage |
| ✅ Multi-cloud portable | ❌ ~$30-100/month (EC2 + storage) |
| ✅ OCSP/CRL built-in | ❌ 2-3 hour deployment |

**Best for:** Organizations already using Vault or needing multi-cloud PKI.

---

### Option 1: EC2 + OpenSSL (Selected - Development/Cost-Optimized)

**Architecture:** OpenSSL-based CA on EC2, software key storage

| Pros | Cons |
|------|------|
| ✅ **Lowest cost (~$10-50/month)** | ❌ No HSM (software keys) |
| ✅ **Fastest deployment (~1 hour)** | ❌ Manual CRL/OCSP setup |
| ✅ Mirrors local development setup | ❌ Key backup responsibility |
| ✅ Full P-384 support | ❌ EC2 maintenance required |
| ✅ Complete certificate customization | ❌ Not FIPS compliant |
| ✅ Familiar OpenSSL tooling | |

**Best for:** Development, testing, non-regulated environments, cost-sensitive deployments.

---

### Option 4: Hybrid ACM PCA (Selected - Production)

**Architecture:** Offline local Root CA + ACM PCA Intermediate CA

| Pros | Cons |
|------|------|
| ✅ **Root CA stays offline (most secure)** | ❌ ~$400/month |
| ✅ FIPS 140-2 Level 3 for Intermediate | ❌ Manual Intermediate renewal |
| ✅ Built-in OCSP and CRL | ❌ Partial vendor lock-in |
| ✅ ~30 minute deployment | |
| ✅ Uses existing local Root CA | |
| ✅ Follows PKI best practices | |

**Best for:** Production environments balancing security, compliance, and cost.

---

## Decision Matrix

| Criteria | Weight | Option 1 (EC2+OpenSSL) | Option 4 (Hybrid ACM) |
|----------|--------|------------------------|----------------------|
| Monthly Cost | 25% | ⭐⭐⭐⭐⭐ (~$15) | ⭐⭐⭐ (~$400) |
| Deployment Speed | 25% | ⭐⭐⭐⭐ (~1 hr) | ⭐⭐⭐⭐⭐ (~30 min) |
| Key Security | 20% | ⭐⭐ (software) | ⭐⭐⭐⭐⭐ (HSM) |
| FIPS Compliance | 15% | ⭐ (none) | ⭐⭐⭐⭐⭐ (L3) |
| Operational Overhead | 15% | ⭐⭐⭐ (EC2 mgmt) | ⭐⭐⭐⭐ (managed) |
| **Weighted Score** | | **3.45** | **4.05** |

---

## Recommendation

### For Development/Testing: **Option 1 (EC2 + OpenSSL)**

- Immediate deployment with minimal cost
- Mirrors local PKI setup for consistency
- Acceptable risk for non-production workloads
- Easy to tear down and recreate

### For Production: **Option 4 (Hybrid ACM PCA)**

- Root CA remains offline (highest security)
- Intermediate CA benefits from managed HSM
- 50% cost reduction vs full ACM PCA
- Follows industry best practices for PKI architecture

---

## Implementation Path

```
Phase 1 (Now): Deploy Option 1 for development/testing
                ↓
Phase 2 (Production): Upgrade to Option 4
                      - Keep local Root CA offline
                      - Create ACM PCA Intermediate
                      - Sign with local Root CA
                      - Migrate subscriber enrollment
```

---

## Cost Summary

| Environment | Option | Monthly | Annual |
|-------------|--------|---------|--------|
| Development | Option 1 (EC2+OpenSSL) | ~$15 | ~$180 |
| Production | Option 4 (Hybrid ACM) | ~$400 | ~$4,800 |
| **Total** | | **~$415** | **~$4,980** |

*vs Full ACM PCA: ~$9,600/year (51% savings)*
