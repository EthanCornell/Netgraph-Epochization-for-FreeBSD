FreeBSD Source:
---------------
This is the top level of the FreeBSD source directory.

FreeBSD is an operating system used to power modern servers, desktops, and embedded platforms.
A large community has continually developed it for more than thirty years.
Its advanced networking, security, and storage features have made FreeBSD the platform of choice for many of the busiest web sites and most pervasive embedded networking and storage devices.

For copyright information, please see [the file COPYRIGHT](COPYRIGHT) in this directory.
Additional copyright information also exists for some sources in this tree - please see the specific source directories for more information.

The Makefile in this directory supports a number of targets for building components (or all) of the FreeBSD source tree.
See build(7), config(8), [FreeBSD handbook on building userland](https://docs.freebsd.org/en/books/handbook/cutting-edge/#makeworld), and [Handbook for kernels](https://docs.freebsd.org/en/books/handbook/kernelconfig/) for more information, including setting make(1) variables.

For information on the CPU architectures and platforms supported by FreeBSD, see the [FreeBSD
website's Platforms page](https://www.freebsd.org/platforms/).

For official FreeBSD bootable images, see the [release page](https://download.freebsd.org/ftp/releases/ISO-IMAGES/).

Source Roadmap:
---------------
| Directory | Description |
| --------- | ----------- |
| bin | System/user commands. |
| cddl | Various commands and libraries under the Common Development and Distribution License. |
| contrib | Packages contributed by 3rd parties. |
| crypto | Cryptography stuff (see [crypto/README](crypto/README)). |
| etc | Template files for /etc. |
| gnu | Commands and libraries under the GNU General Public License (GPL) or Lesser General Public License (LGPL). Please see [gnu/COPYING](gnu/COPYING) and [gnu/COPYING.LIB](gnu/COPYING.LIB) for more information. |
| include | System include files. |
| kerberos5 | Kerberos5 (Heimdal) package. |
| lib | System libraries. |
| libexec | System daemons. |
| release | Release building Makefile & associated tools. |
| rescue | Build system for statically linked /rescue utilities. |
| sbin | System commands. |
| secure | Cryptographic libraries and commands. |
| share | Shared resources. |
| stand | Boot loader sources. |
| sys | Kernel sources (see [sys/README.md](sys/README.md)). |
| targets | Support for experimental `DIRDEPS_BUILD` |
| tests | Regression tests which can be run by Kyua.  See [tests/README](tests/README) for additional information. |
| tools | Utilities for regression testing and miscellaneous tasks. |
| usr.bin | User commands. |
| usr.sbin | System administration commands. |

For information on synchronizing your source tree with one or more of the FreeBSD Project's development branches, please see [FreeBSD Handbook](https://docs.freebsd.org/en/books/handbook/cutting-edge/#current-stable).



---

# Netgraph Optimization for FreeBSD: Concurrency Enhancements

## Project Overview
During **Netgraph Optimization for FreeBSD Project**, I undertook a project to enhance the **Netgraph subsystem** in FreeBSD, focusing on improving concurrency. Netgraph is a graph-based kernel networking subsystem, which allows dynamic configuration of networking topologies using nodes and hooks. The aim was to transition Netgraph's data flow to a lockless model, leveraging epoch-based memory reclamation for improved performance and scalability.

---

## Challenges Addressed
1. **High Lock Contention**: The reliance on **RW locks and mutexes** caused bottlenecks in multi-core environments with high concurrency.
2. **Inefficient Memory Management**: Memory was managed using reference counts, leading to overhead and potential delays in reclamation.
3. **Scalability Constraints**: Increased locking overhead limited the system's scalability under heavy loads.
4. **Complexity of Lock Management**: The use of fine-grained locks introduced the potential for deadlocks and increased code complexity.

---

## Solution: Lockless Data Flow Using Epoch-Based Reclamation
### Key Steps Taken
1. **Review of Existing Locking Mechanisms**: 
   - Analyzed critical sections and evaluated their impact on system performance.
   - Identified parts of the code where locks could be safely replaced by epoch-based reclamation.

2. **Integration of Epoch-Based Reclamation**:
   - Introduced `NET_EPOCH` to manage delayed reclamation of nodes and hooks.
   - Ensured that memory was not freed until it was safe to do so, preventing use-after-free errors.

3. **Core API Redesign**:
   - Updated functions such as `ng_address_hook()` to use epoch mechanisms.
   - Ensured data integrity while enabling lockless operations.

4. **Testing and Validation**:
   - Developed a testbed with stateless nodes (`ng_patch`, `ng_tee`, `ng_ipfw`) for iterative testing.
   - Conducted stress and integration tests to validate functionality and stability.

5. **Performance Optimization**:
   - Profiled the system using tools like DTrace and gprof to measure improvements and pinpoint inefficiencies.
   - Refined the implementation iteratively based on test results.

---

## Performance Bottlenecks Before Optimization
### Without Epochs
- **Lock Contention**: Frequent lock acquisitions caused delays during packet processing.
- **Priority Inversion**: Higher-priority tasks were delayed by low-priority threads holding locks.
- **Latency and Overhead**: Locking mechanisms added unnecessary delays to packet flow.
- **Limited Scalability**: System throughput suffered as the number of threads increased.

---

## Why Epoch-Based Reclamation?
Epoch-based reclamation provides several advantages over traditional locking mechanisms and hazard pointers:
- **Reduced Overhead**: Eliminates frequent lock acquisition and release cycles.
- **Improved Scalability**: Efficiently handles concurrency in multi-threaded systems.
- **Simplicity**: Avoids the complexity of managing fine-grained locks or hazard pointers.
- **Deferred Reclamation**: Ensures safe memory management without blocking threads.

---

## Results and Achievements
1. **Improved Performance**:
   - Reduced locking overhead led to lower latency and higher throughput.
   - Scalability improved significantly under high concurrency conditions.

2. **Enhanced Stability**:
   - Comprehensive testing ensured the lockless design was robust and reliable.

3. **Scalability**:
   - System behavior remained stable as the number of threads increased, proving the feasibility of the lockless design.

4. **Documentation**:
   - Thoroughly documented the design, implementation, and testing methodologies for future reference and contributions.

---

## Example Scenario
### Before Optimization
A two-node Netgraph topology (`ng_patch` ↔ `ng_tee`) processed packets with mutexes, leading to:
- Blocking between read and write operations.
- High CPU usage under load due to lock contention.

### After Optimization
With epoch-based reclamation:
- Nodes exchanged data without locks, reducing contention and improving throughput.
- Memory reclamation was deferred safely until all threads moved past the epoch of the deleted nodes.

---

## Conclusion
This project showcases my ability to:
- **Identify and address performance bottlenecks** in complex systems.
- **Implement scalable, lockless designs** using modern concurrency techniques.
- **Thoroughly test and validate** changes to ensure robustness and stability.

---

## References
- FreeBSD Project Report: [[Link to Full Documentation](https://wiki.freebsd.org/IHsuanHuang)]
- Papers on Epoch-Based Reclamation: [[Additional References](https://par.nsf.gov/servlets/purl/10072834)]

