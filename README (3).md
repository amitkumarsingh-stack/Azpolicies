Their research is mostly right. I’d correct two points and add one thing they missed:

API server: correct. Microsoft manages it and AKS has no TLS setting for it. That doesn’t mean it lacks TLS 1.3, though. It’s Go-based and should already negotiate 1.3 with modern clients. A quick openssl s_client -tls1_3 against the endpoint will confirm it instead of leaving it as “if and when MS supports it”.
Nodes: needs a correction. Workloads don’t serve traffic from the node OS. The only TLS endpoint on a node is the kubelet, which is cluster-internal and managed by AKS. As far as I know, AKS’s custom node configuration doesn’t expose a kubelet TLS-version setting. So the nodes aren’t the place to meet a CISO requirement.
Ingress and load balancers: correct, with one fix. Azure Load Balancer works at layer 4 and never terminates TLS, so there’s no TLS version to set on it. Termination happens at the ingress controller or App Gateway, and that’s where you’d enforce 1.3.
What’s missing: outbound TLS from pods to Azure services such as Storage, SQL and Key Vault. Their minimum TLS version is set on each of those resources, not in AKS.
