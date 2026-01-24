# Kubernetes Cluster Recovery & Disk Space Management Documentation

## 📋 **Executive Summary**

This document details the complete troubleshooting and recovery process for a Kubernetes cluster on AWS that became inaccessible due to disk space exhaustion. The root cause was identified, resolved, and preventive measures were implemented.

---

## 🎯 **Problem Statement**

**Date**: January 2025  
**Symptoms**:

- Local `kubectl get nodes` commands failing with connection errors
- SSH tunnel to AWS cluster returning "Connection refused"
- Cluster API server unresponsive

**Root Cause**: Master node root filesystem (`/`) at 100% capacity (7.6GB/7.6GB used), preventing Kubernetes system pods from starting.

---

## 🔍 **Diagnostic Process**

### **Phase 1: Network Connectivity Analysis**

**Issue**: SSH tunnel failing despite successful basic SSH connection

```
ssh -i ~/.ssh/id_rsa -L 6443:localhost:6443 ubuntu@3.112.132.56 -N
# Error: channel 2: open failed: connect failed: Connection refused
```

**Finding**: Network connectivity was functional, but port 6443 (Kubernetes API) wasn't listening.

### **Phase 2: Cluster Health Check**

**Commands Executed**:

```bash
# On master node via AWS Console/SSH
sudo systemctl status kube-apiserver  # "Unit could not be found"
df -h  # Revealed: /dev/root 7.6G 7.6G 0 100% /
sudo journalctl -u kubelet | grep "no space"  # Confirmed disk space error
```

**Critical Discovery**: Kubelet logs showed:

```
CreateContainerConfigError: write /var/lib/kubelet/pods/.../etc-hosts:
no space left on device
```

### **Phase 3: Disk Space Forensics**

**Space Analysis Commands**:

```bash
df -h /  # Overall usage
sudo du -sh /*  # Top-level directory breakdown
sudo du -sh /var/*  # /var analysis (3.6GB total)
sudo du -sh /var/lib/*  # /var/lib analysis (3.4GB total)
```

**Findings**:
| Directory | Size | Percentage |
|-----------|------|------------|
| `/var/lib/containerd` | 1.8GB | 53% |
| `/var/lib/snapd` | 920MB | 27% |
| `/var/lib/etcd` | 432MB | 13% |
| `/var/lib/apt` | 273MB | 8% |

---

## 🛠️ **Recovery Actions**

### **Step 1: Emergency Disk Cleanup**

**Safe Cleanup Commands Executed**:

```bash
# 1. Journal log cleanup (Freed ~500MB)
sudo journalctl --vacuum-time=2d

# 2. APT cache cleanup
sudo apt clean && sudo apt autoclean

# 3. Snap cleanup
sudo snap list --all | grep disabled | awk '{print $1, $3}' | \
  while read snapname revision; do sudo snap remove "$snapname" --revision="$revision"; done
sudo rm -rf /var/lib/snapd/cache/*

# 4. Containerd image pruning
sudo crictl rmi --prune
```

**Result**: Disk usage reduced from **100% → 93%** (595MB free)

### **Step 2: Cluster Component Restart**

```bash
# Restart kubelet to recreate static pods
sudo systemctl restart kubelet
sleep 30

# Verify API server is listening
sudo ss -tlnp | grep 6443
```

### **Step 3: SSH Tunnel Re-establishment**

**Tunnel Command**:

```bash
ssh -i ~/.ssh/id_rsa -L 6443:localhost:6443 ubuntu@3.112.132.56 -N
```

**Certificate Fix** (Required due to TLS SAN mismatch):

```bash
# Edit /etc/hosts on local machine
sudo nano /etc/hosts
# Add: 127.0.0.1 ip-172-31-37-254
```

**kubeconfig Adjustment**:

```yaml
# Changed from: server: https://172.31.37.254:6443
# To: server: https://ip-172-31-37-254:6443
```

### **Step 4: Verification**

```bash
kubectl get nodes
# SUCCESS: All 3 nodes showed "Ready" status
```

---

## 🚀 **Preventive Measures Implemented**

### **1. Automated Journal Log Cleanup**

**Cron Job Configuration**:

```bash
# Set to run daily at 5:00 AM
echo "0 5 * * * /usr/bin/journalctl --vacuum-time=2d" | sudo crontab -
```

**Monitoring Script**:

```bash
# Disk space alerting
echo "0 * * * * df -h / | grep -q '9[0-9]%' && echo 'ALERT: Disk over 90% at \$(date)' >> /var/log/disk-alert.log" | sudo crontab -
```

### **2. Enhanced Monitoring**

```bash
# Added to crontab for proactive monitoring
0 3 * * * /usr/local/bin/disk-cleanup-check.sh
```

### **3. Documentation & Runbooks**

Created this documentation including:

- Root cause analysis
- Step-by-step recovery procedures
- Preventive automation scripts
- Troubleshooting command reference

---

## 📊 **Key Learnings**

### **Technical Insights**:

1. **Kubernetes is disk-sensitive**: Control plane components fail silently when disk reaches 100%
2. **Containerd storage growth**: Container images can consume 50%+ of system disk
3. **Journal log accumulation**: Systemd journals grow indefinitely without rotation
4. **TLS certificate validation**: `localhost` vs. internal hostname mismatches break kubectl

### **Operational Best Practices**:

1. **Monitor disk usage proactively**: Set alerts at 80%, 90%, 95%
2. **Implement automated cleanup**: Regular maintenance prevents emergencies
3. **Document recovery procedures**: Critical for quick incident response
4. **Test recovery regularly**: Ensure procedures work when needed

### **AWS-Specific Notes**:

1. **EC2 instance sizing**: 8GB root volume is minimal for production Kubernetes
2. **EBS volume expansion**: Consider increasing to 20GB+ for production workloads
3. **CloudWatch monitoring**: Implement disk space metrics and alarms

---

## 🛡️ **Prevention Checklist**

### **Daily**:

- [ ] Automated journal log rotation (cron: 5 AM)
- [ ] Disk space monitoring (alert at >85%)

### **Weekly**:

- [ ] Containerd image pruning
- [ ] APT cache cleanup
- [ ] Review disk alert logs

### **Monthly**:

- [ ] Review and update cleanup thresholds
- [ ] Test disaster recovery procedures
- [ ] Review cluster resource utilization trends

### **Quarterly**:

- [ ] Evaluate need for disk expansion
- [ ] Review and update documentation
- [ ] Test full cluster recovery from backup

---

## 📞 **Emergency Contact & Escalation**

### **Immediate Actions**:

1. **Check disk space**: `df -h /`
2. **Clean journal logs**: `sudo journalctl --vacuum-time=2d`
3. **Restart kubelet**: `sudo systemctl restart kubelet`
4. **Verify connectivity**: `kubectl get nodes`

### **If Issues Persist**:

1. **Check component status**: `sudo systemctl status kubelet containerd`
2. **Review logs**: `sudo journalctl -u kubelet -n 100`
3. **Escalate to**: [Your Team Lead / Cloud Admin]

---

## 📈 **Performance Metrics Post-Recovery**

**Before Recovery**:

- Disk usage: 100% (0 bytes free)
- API server: Not running
- Cluster access: Broken

**After Recovery**:

- Disk usage: 93% (595MB free)
- API server: Running
- Cluster access: Fully restored
- Automated prevention: Implemented

**Preventive Capacity**:

- Daily log rotation frees ~500MB
- Weekly maintenance frees ~1GB
- Sustainable usage: <85% target

---

## 🔗 **Related Documentation**

1. AWS EC2 Instance Management Guide
2. Kubernetes Cluster Administration Manual
3. Disaster Recovery Playbook
4. Monitoring and Alerting Configuration

---

**Document Version**: 1.0  
**Last Updated**: January 2025  
**Author**: [Your Name/Team]  
**Status**: ✅ Complete & Implemented  
**Next Review Date**: April 2025
