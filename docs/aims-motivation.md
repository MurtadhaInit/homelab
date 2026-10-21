# Overall aims and motivation

I aim for this homelab to be a learning and experimentation playground, where I
can try different tools (for evaluation) or services (to see if they add value to
my life). I also gain the benefit of privacy, digital sovereignty, and data ownership.
Plus homelabbing and self-hosting are just fun; they quickly turned into an addictive
hobby on their own.

The reason I'm using what some would consider "overkill" technologies and platforms
(like k8s) for a homelab setup is that I also want my own home infrastructure to
be as closely aligned as possible to industry standards and to enterprise tooling
and tech stacks.

Flexibility is another goal. E.g., one would ask, why not deploy k8s on bare metal
and skip the Proxmox abstraction layer entirely (along with its maintenance
overhead)? The simple answer is flexibility: what if I want to run other
VMs? or to quickly deploy and experiment with some new technology? or to play with
Docker/Podman? or even to use Windows Server for some reason (I have a VM definition
ready)?

This flexible setup also allows me to make use of two different approaches for deploying
and configuring applications, and without much hassle: declarative `systemd` services
in the form of NixOS modules, and containerised applications running on a platform
like Docker or k8s. This is arguably the best of both worlds: combining the enterprise
scalability of a robust, widely-adopted platform like k8s and the relative
"simplicity" or straightforwardness of declarative NixOS services.
