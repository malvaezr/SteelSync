import WidgetKit
import SwiftUI

@main
struct SteelSyncWidgetBundle: WidgetBundle {
    var body: some Widget {
        SummaryWidget()
        TodoOverviewWidget()
        BidPipelineWidget()
        GanttPreviewWidget()
        InvoiceAgingWidget()
        ForemanBonusWidget()
        TodayAttentionWidget()
        EquipmentRentalWidget()
        NextMilestoneWidget()
        #if os(iOS)
        RentalLiveActivityWidget()
        CrewClockInLiveActivityWidget()
        #endif
    }
}
