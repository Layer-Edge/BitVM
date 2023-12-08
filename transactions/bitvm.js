import { merkleSequence } from './merkle-sequence.js'
import { u32_add_drop } from '../scripts/opcodes/u32_add.js'
import { u32_sub_drop } from '../scripts/opcodes/u32_sub.js'
import { Leaf } from './transaction.js'

import {
    binarySearchSequence,
    TRACE_CHALLENGE,
    TRACE_RESPONSE
} from './binary-search-sequence.js'

import {
    u32_toaltstack,
    u32_fromaltstack,
    u32_equalverify,
    u32_equal,
    u32_push,
    u32_drop,
    u32_notequal
} from '../scripts/opcodes/u32_std.js'


// Logarithm of the length of the trace
export const LOG_TRACE_LEN = 4
export const TRACE_LEN = 2 ** LOG_TRACE_LEN


// Challenges
export const CHALLENGE_EXECUTION = 'CHALLENGE_EXECUTION'
export const CHALLENGE_INSTRUCTION = 'CHALLENGE_INSTRUCTION'
export const CHALLENGE_VALUE_A = 'CHALLENGE_VALUE_A'
export const CHALLENGE_VALUE_B = 'CHALLENGE_VALUE_B'
export const CHALLENGE_VALUE_C = 'CHALLENGE_VALUE_C'
export const CHALLENGE_PC_CURR = 'CHALLENGE_PC_CURR'



// Instructions
export const ASM_ADD = 42;
export const ASM_SUB = 43;
export const ASM_MUL = 44;
export const ASM_JMP = 45;
export const ASM_BEQ = 46;
export const ASM_BNE = 47;
// ...


// A program is a list of instructions
class Instruction {
    constructor(type, addressA, addressB, addressC) {
        this.type = type
        this.addressA = addressA
        this.addressB = addressB
        this.addressC = addressC
    }
}

export const compileProgram = source => source.map(instruction => new Instruction(...instruction))


class CommitInstructionLeaf extends Leaf {
    // TODO: use a register instead, so instructions become more compact and fit into 32 bits 

    lock(vicky, paul) {
        return [
            paul.commit.pcCurr,
            paul.commit.pcNext,
            paul.commit.type,
            paul.commit.addressA,
            paul.commit.valueA,
            paul.commit.addressB,
            paul.commit.valueB,
            paul.commit.addressC,
            paul.commit.valueC,

            OP_TRUE,
        ]
    }

    // TODO: Set the values in the state before this is called
    unlock(vicky, paul) {
        return [
            paul.unlock.valueC,
            paul.unlock.addressC,
            paul.unlock.valueB,
            paul.unlock.addressB,
            paul.unlock.valueA,
            paul.unlock.addressA,
            paul.unlock.type,
            paul.unlock.pcNext,
            paul.unlock.pcCurr,
        ]
    }
}

const commitInstructionRoot = (vicky, paul) => [
    [CommitInstructionLeaf, vicky, paul]
]



class ChallengeInstructionLeaf extends Leaf {

    lock(vicky, identifier) {
        return [
            OP_RIPEMD160,
            vicky.hashlock(identifier),
            OP_EQUAL,
        ]
    }

    unlock(vicky, identifier) {
        return [
            vicky.preimage(identifier)
        ]
    }
}




// Vicky disproves an execution of Paul 
class ExecuteAddLeaf extends Leaf {

    lock(vicky, paul) {
        return [
            // Vicky can execute only the instruction which Paul committed to
            paul.commit_stack.type,
            ASM_ADD,
            OP_EQUALVERIFY,

            // Show that A + B does not equal C
            paul.commit_stack.valueA,
            u32_toaltstack,

            paul.commit_stack.valueB,
            u32_toaltstack,

            paul.commit_stack.valueC, // Disproving a single bit of C would suffice

            u32_fromaltstack,
            u32_fromaltstack,
            u32_add_drop(0, 1),
            u32_notequal,
        ]
    }
    // TODO: Verify the covenant
    unlock(vicky, paul) {
        return [
            paul.unlock.valueC,
            paul.unlock.valueB,
            paul.unlock.valueA,
            paul.unlock.type
            // TODO: vicky signs
        ]
    }
}


class ExecuteSubLeaf extends Leaf {

    lock(vicky, paul) {
        return [
            // Vicky can execute only the instruction which Paul committed to
            paul.commit_stack.type,
            ASM_SUB,
            OP_EQUALVERIFY,

            // Show that A - B does not equal C
            paul.commit_stack.valueA,
            u32_toaltstack,

            paul.commit_stack.valueB,
            u32_toaltstack,

            paul.commit_stack.valueC, // Disproving a single bit of C would suffice

            u32_fromaltstack,
            u32_fromaltstack,
            u32_sub_drop(0, 1),
            u32_notequal,
        ]
    }

    unlock(vicky, paul) {
        return [
            paul.unlock.valueC,
            paul.unlock.valueB,
            paul.unlock.valueA,
            paul.unlock.type
            // TODO: vicky signs
        ]
    }
}




class ExecuteJmpLeaf extends Leaf {

    lock(vicky, paul) {
        return [
            // Vicky can execute only the instruction which Paul committed to
            paul.commit_stack.type,
            ASM_JMP,
            OP_EQUALVERIFY,

            // Show that pcNext does not equal A
            paul.commit_stack.pcNext,
            u32_toaltstack,

            paul.commit_stack.valueA,

            u32_fromaltstack,
            u32_notequal,
        ]
    }

    unlock(vicky, paul) {
        return [
            paul.unlock.valueC,
            paul.unlock.pcNext,
            paul.unlock.type
        ]
    }
}


// Execute BEQ, "Branch if equal"
class ExecuteBEQLeaf extends Leaf {

    lock(vicky, paul) {
        return [
            paul.commit_stack.type,
            ASM_BEQ,
            OP_EQUALVERIFY,

            paul.commit_stack.pcNext,
            u32_toaltstack,

            // Read the current program counter, add 1, and store for later
            paul.commit_stack.pcCurr,
            u32_push(1),
            u32_add_drop(0, 1),
            u32_toaltstack,

            paul.commit_stack.valueC,
            u32_toaltstack,

            paul.commit_stack.valueB,
            u32_toaltstack,

            paul.commit_stack.valueA,
            u32_fromaltstack,

            u32_equal,
            u32_fromaltstack,

            4, OP_ROLL, // Result of u32_equal
            OP_IF,
            u32_fromaltstack,
            u32_drop,
            OP_ELSE,
            u32_drop,
            u32_fromaltstack,
            OP_ENDIF,

            u32_fromaltstack,
            u32_notequal,

        ]
    }

    unlock(vicky, paul) {
        return [
            paul.unlock.valueA,
            paul.unlock.valueB,
            paul.unlock.valueC,
            paul.unlock.pcCurr,
            paul.unlock.pcNext,
            paul.unlock.type,
        ]
    }
}


const instructionExecutionRoot = (vicky, paul) => [
    [ExecuteAddLeaf, vicky, paul],
    [ExecuteSubLeaf, vicky, paul],
    [ExecuteJmpLeaf, vicky, paul],
    [ExecuteBEQLeaf, vicky, paul],
]




// For each instruction in the program we create an instruction leaf
class InstructionLeaf extends Leaf {

    // Todo add a leaf for unary instructions
    // TODO: make a separate leaf to disprove addressA, addressB, addressC, ...  
    // Actually, disproving a single bit suffices !!
    
    // TODO: Further refactor to paul.commit api?
    lock(vicky, paul, pcCurr, instruction) {
        return [
            // Ensure Vicky is executing the correct instruction here
            paul.commit_stack.pcCurr,
            u32_push(pcCurr),
            u32_notequal,
            OP_TOALTSTACK,

            paul.commit_stack.type,
            instruction.type,
            OP_NOTEQUAL,
            OP_TOALTSTACK,

            paul.commit_stack.addressA,
            u32_push(instruction.addressA),
            u32_notequal,
            OP_TOALTSTACK,

            paul.commit_stack.addressB,
            u32_push(instruction.addressB),
            u32_notequal,
            OP_TOALTSTACK,

            paul.commit_stack.addressC,
            u32_push(instruction.addressC),
            u32_notequal,

            OP_FROMALTSTACK,
            OP_FROMALTSTACK,
            OP_FROMALTSTACK,
            OP_FROMALTSTACK,
            OP_BOOLOR,
            OP_BOOLOR,
            OP_BOOLOR,
            OP_BOOLOR,

            // TODO: vicky should sign!
        ]
    }

    unlock(vicky, paul) {
        return [
            paul.unlock.valueC,
            paul.unlock.valueB,
            paul.unlock.valueA,
            paul.unlock.type,
            paul.unlock.pcCurr
        ]
    }
}

// Create an InstructionLeaf for every instruction in the program
const programRoot = (vicky, paul, program) =>
    program.map((instruction, index) => [InstructionLeaf, vicky, paul, index, new Instruction(instruction)])



const challengeInstructionRoot = (vicky, paul, program) => [
    [ChallengeInstructionLeaf, vicky, CHALLENGE_VALUE_A],
    [ChallengeInstructionLeaf, vicky, CHALLENGE_VALUE_B],
    [ChallengeInstructionLeaf, vicky, CHALLENGE_VALUE_C],
    [ChallengeInstructionLeaf, vicky, CHALLENGE_PC_CURR],
    ...instructionExecutionRoot(vicky, paul),
    ...programRoot(vicky, paul, program),
]


const mergeSequences = (sequenceA, sequenceB) => {
    const length = Math.max(sequenceA.length, sequenceB.length)
    const result = []
    for (let i = 0; i < length; i++) {
        const a = sequenceA[i] || []
        const b = sequenceB[i] || []
        result[i] = [...a, ...b]
    }
    return result
}


class KickOffLeaf extends Leaf {

    lock(vicky) {
        return [
            vicky.pubkey,
            OP_CHECKSIG
        ]
    }

    unlock(vicky) {
        return [
            vicky.sign(this)
        ]
    }

}

const kickOffRoot = vicky => [
    [KickOffLeaf, vicky]
]

export const bitvmSequence = (vicky, paul, program) => [
    kickOffRoot(vicky),
    ...binarySearchSequence(vicky, paul, TRACE_CHALLENGE, TRACE_RESPONSE, LOG_TRACE_LEN),
    commitInstructionRoot(vicky, paul),
    challengeInstructionRoot(vicky, paul, program),
    ...merkleSequence(vicky, paul),
]


//class VickyState extends State {
//    
//    get traceIndex() {
//        let traceIndex = 0
//        for (var i = 0; i < LOG_TRACE_LEN; i++) {
//            const bit = this.get_u1( TRACE_CHALLENGE(i) )
//            traceIndex += bit * 2 ** (LOG_TRACE_LEN - i)
//        }
//        return traceIndex
//    }
//
//    get_nextTraceIndex(roundIndex) {
//        let traceIndex = 0
//        for (var i = 0; i < roundIndex; i++) {
//            const bit = this.get_u1( TRACE_CHALLENGE(i) )
//            traceIndex += bit * 2 ** (LOG_TRACE_LEN - i)
//        }
//        traceIndex += 2 ** (LOG_TRACE_LEN - roundIndex)
//        return traceIndex
//    }
//
//
//    get merkleIndex() {
//        let merkleIndex = 0
//        for (var i = 0; i < H; i++) {
//            const bit = this.get_u1( MERKLE_CHALLENGE(i) )
//            merkleIndex += bit * 2 ** (H - i)
//        }
//        return merkleIndex
//    }
//
//    get_nextMerkleIndex(roundIndex) {
//        let merkleIndex = 0
//        for (var i = 0; i < roundIndex; i++) {
//            const bit = this.get_u1( MERKLE_CHALLENGE(i) )
//            merkleIndex += bit * 2 ** (H - i)
//        }
//        merkleIndex += 2 ** (H - roundIndex)
//        return merkleIndex
//    }
//
//
//}
//
//class PaulState extends State {
//
//    get_traceResponse(roundIndex) {
//        return this.get_u160(TRACE_RESPONSE(roundIndex))
//    }
//
//    get_merkleResponse(roundIndex) {
//        return this.get_u160(MERKLE_RESPONSE(roundIndex))
//    }
//
//    get valueA(){
//        return this.u32(INSTRUCTION_VALUE_A)
//    }
//
//    get valueB(){
//        return this.u32(INSTRUCTION_VALUE_B)
//    }
//
//    get valueC(){
//        return this.u32(INSTRUCTION_VALUE_C)
//    }
//}
//