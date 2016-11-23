# Elbtool

Register and deregister instance from an AWS ELB

# Requirements

* Instance must be a member of an IAM role with the proper permissions
* `aws-sdk`

# Usage

Originally this was intended to be used by automatic reboot scripts to deregister instances before shutting them down, but it can also be triggered manually.

Note that if you are **NOT** running on the EC2 instance you want to (de-)register, you will need to specify `--instance-id INSTANCE_ID`.

## To register an instance

```
$ elbtool --register LOAD_BALANCER_NAME
```

## To de-register an instance

```
$ elbtool --deregister LOAD_BALANCER_NAME
```

## Other important options

* `--register-timeout` -- Number of seconds to wait when registering an instance before giving up and returning an error. By default this is set to the health check `interval` times `healthy_threshold` (the number of times an instance must return a successful health check to be considered health) plus 15 seconds (for buffer)
* `--deregister-timeout` -- Number of seconds to wait when de-registering an instance before giving up and returning an error. If connection draining is enabled, this waits for `connection_draining` + 5 seconds. If not, it just waits 5 seconds (for buffer).
