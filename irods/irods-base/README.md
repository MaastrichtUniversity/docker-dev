This image comes in two flavors: `ubuntu` and `centos`.

An additional `Dockerfile-full.ubuntu` is provided. This `-full` images takes
a different approach, in which as much as possible is installed in the base
image. This is in opposition to the other base images, in which only the
minimum amount of packages/files are installed -- only the stuff that will be
shared across multiple derived images such as icat, ires, etc.

So, `-full` will include stuff to mount `CIFS` file systems in case a derived
`ires` image uses it. While the non-`full` version will not include that.

