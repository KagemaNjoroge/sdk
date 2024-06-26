// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/pending_deopts.h"
#include "vm/log.h"
#include "vm/stack_frame.h"
#include "vm/stub_code.h"

namespace dart {

DECLARE_FLAG(bool, trace_deoptimization);

PendingDeopts::PendingDeopts()
    : pending_deopts_(new MallocGrowableArray<PendingLazyDeopt>()) {}
PendingDeopts::~PendingDeopts() {
  delete pending_deopts_;
  pending_deopts_ = nullptr;
}

void PendingDeopts::AddPendingDeopt(uword fp, uword pc) {
  // GrowableArray::Add is not atomic and may be interrupted by a profiler
  // stack walk.
  MallocGrowableArray<PendingLazyDeopt>* old_pending_deopts = pending_deopts_;
  MallocGrowableArray<PendingLazyDeopt>* new_pending_deopts =
      new MallocGrowableArray<PendingLazyDeopt>(old_pending_deopts->length() +
                                                1);
  for (intptr_t i = 0; i < old_pending_deopts->length(); i++) {
    ASSERT((*old_pending_deopts)[i].fp() != fp);
    new_pending_deopts->Add((*old_pending_deopts)[i]);
  }
  PendingLazyDeopt deopt(fp, pc);
  new_pending_deopts->Add(deopt);

  pending_deopts_ = new_pending_deopts;
  delete old_pending_deopts;
}

PendingLazyDeopt* PendingDeopts::FindPendingDeoptRecord(uword fp) {
  for (intptr_t i = 0; i < pending_deopts_->length(); i++) {
    if ((*pending_deopts_)[i].fp() == fp) {
      return &(*pending_deopts_)[i];
    }
  }
  return nullptr;
}

uword PendingDeopts::FindPendingDeopt(uword fp) {
  auto record = FindPendingDeoptRecord(fp);
  if (record != nullptr) {
    return record->pc();
  }
  FATAL("Missing pending deopt entry");
  return 0;
}

void PendingDeopts::ClearPendingDeoptsBelow(uword fp, ClearReason reason) {
  for (intptr_t i = pending_deopts_->length() - 1; i >= 0; i--) {
    if ((*pending_deopts_)[i].fp() < fp) {
      if (FLAG_trace_deoptimization) {
        switch (reason) {
          case kClearDueToThrow:
            THR_Print(
                "Lazy deopt skipped due to throw for "
                "fp=%" Pp ", pc=%" Pp "\n",
                (*pending_deopts_)[i].fp(), (*pending_deopts_)[i].pc());
            break;
          case kClearDueToDeopt:
            THR_Print("Lazy deopt fp=%" Pp " pc=%" Pp "\n",
                      (*pending_deopts_)[i].fp(), (*pending_deopts_)[i].pc());
            break;
        }
      }
      pending_deopts_->RemoveAt(i);
    }
  }
}

void PendingDeopts::ClearPendingDeoptsAtOrBelow(uword fp, ClearReason reason) {
  ClearPendingDeoptsBelow(fp + kWordSize, reason);
}

uword PendingDeopts::RemapExceptionPCForDeopt(uword program_counter,
                                              uword frame_pointer,
                                              bool* clear_deopt) {
  *clear_deopt = false;

  // Do not attempt to deopt at async exception handler as it doesn't
  // belong to the function code. Async handler never continues execution
  // in the same frame - it either rethrows exception to the caller or
  // tail calls Dart handler, leaving the function frame before the call.
  if (program_counter == StubCode::AsyncExceptionHandler().EntryPoint()) {
    *clear_deopt = true;
    return program_counter;
  }

  // Check if the target frame is scheduled for lazy deopt.
  if (FindPendingDeoptRecord(frame_pointer) != nullptr) {
#if defined(DEBUG)
    // Ensure the frame references optimized code.
    ObjectPtr pc_marker = *(reinterpret_cast<ObjectPtr*>(
        frame_pointer + runtime_frame_layout.code_from_fp * kWordSize));
    Code& code = Code::Handle(Code::RawCast(pc_marker));
    ASSERT(code.is_optimized() && !code.is_force_optimized());
#endif
    if (FLAG_trace_deoptimization) {
      THR_Print("Throwing to frame scheduled for lazy deopt fp=%" Pp "\n",
                frame_pointer);
    }
    return StubCode::DeoptimizeLazyFromThrow().EntryPoint();
  }

  return program_counter;
}

}  // namespace dart
